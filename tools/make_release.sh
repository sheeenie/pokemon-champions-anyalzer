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
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo
echo "Release file: $ZIP ($(du -h "$ZIP" | cut -f1))"
echo "Architectures: $ARCHS"
echo "SHA-256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
