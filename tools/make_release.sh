#!/bin/bash
# Builds the app and zips it for a GitHub Release.
# usage: tools/make_release.sh <version>    e.g. tools/make_release.sh 1.0.0
set -e

VERSION="${1:?usage: tools/make_release.sh <version, e.g. 1.0.0>}"
cd "$(dirname "$0")/.."

# The sprites are packed into the executable, so a release built without them
# would launch fine but never identify anything.
SPRITES=$(ls Resources/icons 2>/dev/null | wc -l | tr -d ' ')
if [ "$SPRITES" -lt 700 ]; then
    echo "Only $SPRITES sprites in Resources/icons - run: python3 tools/fetch_pokedex.py"
    exit 1
fi

VERSION="$VERSION" ./build.sh

# build.sh copies adb from the build machine, so a machine without one produces
# a release that silently makes every Android user install it themselves - the
# app still runs, which is exactly why this would go unnoticed.
if [ ! -x "Pokémon Champions Analyzer.app/Contents/Helpers/adb" ]; then
    echo "No adb in the bundle - install it with: brew install --cask android-platform-tools"
    exit 1
fi

APP="Pokémon Champions Analyzer.app"
BIN="$APP/Contents/MacOS/PokemonChampionsAnalyzer"
codesign --verify --strict "$APP"
ARCHS=$(lipo -archs "$BIN")
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || { echo "Not universal: $ARCHS"; exit 1; }

# Notarize when the app carries a Developer ID. Signing alone does not stop
# macOS blocking the download - Apple has to have seen the build - so a signed
# but un-notarized release would look finished and behave exactly like an
# unsigned one for whoever downloads it. Better to stop here than ship that.
NOTARIZE=""
if codesign -dvv "$APP" 2>&1 | grep -q "Authority=Developer ID Application"; then
    NOTARIZE=1
    NOTARY_PROFILE="${NOTARY_PROFILE:-notary}"
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "Signed with a Developer ID but no notary credentials named '$NOTARY_PROFILE'."
        echo "Create them once with:"
        echo "  xcrun notarytool store-credentials $NOTARY_PROFILE \\"
        echo "      --apple-id <your Apple ID> --team-id <your team id> --password <app-specific password>"
        exit 1
    fi
fi

mkdir -p dist
ZIP="dist/PokemonChampionsAnalyzer-$VERSION.zip"
rm -f "$ZIP"
# ditto keeps the bundle intact (unlike a plain zip of the folder).
#
# --sequesterRsrc has to stay, even though it is what leaves a __MACOSX folder
# beside the app when the zip is opened. macOS puts a com.apple.provenance
# extended attribute on every file in the bundle, including the _CodeSignature
# folder that codesign itself writes, and that attribute is restricted: xattr
# -cr does not remove it, before or after signing. Without sequestering, ditto
# stores those attributes as AppleDouble members, and command-line unzip
# unpacks them as ._ files inside the bundle, which breaks the seal - the
# unzipped app then fails codesign --verify and macOS calls it damaged. Opening
# the zip from Finder handles either form, but a junk folder is a much smaller
# problem than an app that will not open.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

if [ -n "$NOTARIZE" ]; then
    # Apple scans the zip, but the ticket is stapled to the app inside it, so
    # the app has to be re-zipped afterwards. Without stapling the app still
    # passes - macOS asks Apple at first launch - but only with a network
    # connection, which is not a thing to depend on.
    echo "Notarizing (a few minutes)..."
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

    # The verdict that matters: this is what Gatekeeper will say on the
    # machine that downloads it.
    xcrun stapler validate "$APP"
    spctl -a -vv "$APP"
fi

echo
echo "Release file: $ZIP ($(du -h "$ZIP" | cut -f1))"
echo "Architectures: $ARCHS"
echo "SHA-256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
