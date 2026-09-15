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

APP="Pokémon Champions Analyzer.app"
BIN="$APP/Contents/MacOS/PokemonChampionsAnalyzer"
codesign --verify --strict "$APP"
ARCHS=$(lipo -archs "$BIN")
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || { echo "Not universal: $ARCHS"; exit 1; }

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

echo
echo "Release file: $ZIP ($(du -h "$ZIP" | cut -f1))"
echo "Architectures: $ARCHS"
echo "SHA-256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
