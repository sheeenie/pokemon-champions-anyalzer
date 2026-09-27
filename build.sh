#!/bin/bash
set -e

# Shown in Finder, the Dock and the menu bar.
DISPLAY_NAME="Pokémon Champions Analyzer"
# The program file inside the bundle: no spaces or accents, to keep scripts simple.
APP_NAME="PokemonChampionsAnalyzer"
# macOS keys the camera permission and saved settings to this.
BUNDLE_ID="io.github.sheeenie.pokemon-champions-analyzer"
APP_DIR="$DISPLAY_NAME.app"
VERSION="${VERSION:-1.0.0}"
# Oldest macOS the build targets. The code uses macOS 13 APIs (SwiftUI Grid and
# Layout); without an explicit target swiftc uses the build machine's version.
MIN_MACOS="13.0"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

# Create directories. Everything the app loads is linked into the executable
# (below), so Resources holds only the app icon, which Finder and the Dock read
# from a file in the bundle. Clear out anything left by an older build.
mkdir -p "$MACOS_DIR"
rm -rf "$RESOURCES_DIR"
mkdir -p "$RESOURCES_DIR"
cp Assets/AppIcon.icns "$RESOURCES_DIR/AppIcon.icns"

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSCameraUsageDescription</key>
    <string>We need access to capture the iPhone screen.</string>
</dict>
</plist>
EOF

# Pack Resources/ (sprites from tools/fetch_pokedex.py, type icons,
# pokedex.json) into one blob, linked into the executable as a section that
# EmbeddedResources.swift reads. The built app then needs no files beside it.
BLOB="build/resources.bin"
python3 tools/pack_resources.py Resources "$BLOB"

# -O matters here: the icon matcher is a tight per-pixel loop, and unoptimized
# it took ~2.7s per frame (all four slots) against ~50ms optimized, which showed
# up as a multi-second delay before a Pokemon was identified.
SOURCES=(
    main.swift
    CaptureManager.swift
    CameraPreview.swift
    BattleGeometry.swift
    CaptureProfile.swift
    AndroidDirect.swift
    H264Decoder.swift
    BattleAnalyzer.swift
    BattleState.swift
    IconMatcher.swift
    PokedexStore.swift
    StatsPanel.swift
    TypeChart.swift
    TypeIcons.swift
    Localization.swift
    EmbeddedResources.swift
    Diagnostics.swift
    HoverTip.swift
    DamageCalc.swift
    UsageStore.swift
)

# Build for Apple Silicon and Intel, then combine into one universal executable.
# Each slice carries its own copy of the resources, so the executable is about
# twice the size of the packed resources.
for ARCH in arm64 x86_64; do
    swiftc -O -parse-as-library \
        -target "$ARCH-apple-macos$MIN_MACOS" \
        -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __resources -Xlinker "$BLOB" \
        "${SOURCES[@]}" \
        -o "build/$APP_NAME-$ARCH"
done
lipo -create "build/$APP_NAME-arm64" "build/$APP_NAME-x86_64" -output "$MACOS_DIR/$APP_NAME"

# Carry adb, so an Android phone needs nothing installed on the Mac. Copied
# from whichever adb this machine has; without one the app falls back to
# searching the usual paths at runtime, exactly as it did before. A release
# must not be built that way - tools/make_release.sh refuses to.
# Sign with a Developer ID when the machine has one, and ad-hoc otherwise.
#
# A Developer ID signature is only half of what removes the "Apple could not
# verify" block: the app also has to be notarized, which tools/make_release.sh
# does. Notarization in turn requires the hardened runtime, and requires every
# nested executable - adb, here - to carry the same team's signature, which is
# why adb is re-signed below rather than left as it came.
# No colon in the default: setting SIGN_ID to empty deliberately opts out and
# builds ad-hoc. That matters because a Developer ID signature without
# notarization is worse than none - macOS refuses to launch it even locally -
# so there has to be a way back that does not mean deleting the certificate.
SIGN_ID="${SIGN_ID-$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')}"
if [ -n "$SIGN_ID" ]; then
    SIGN_ARGS=(--options runtime --timestamp --sign "$SIGN_ID")
    # Only the app itself: adb needs the hardened runtime but no camera.
    APP_SIGN_ARGS=(--entitlements Hardened.entitlements)
    echo "Signing as: $SIGN_ID"
else
    # Apple Silicon won't run unsigned code at all, so even an unsigned build
    # has to be sealed somehow.
    SIGN_ARGS=(--sign -)
    APP_SIGN_ARGS=()
fi

HELPERS_DIR="$APP_DIR/Contents/Helpers"
rm -rf "$HELPERS_DIR"
for CANDIDATE in /opt/homebrew/bin/adb /usr/local/bin/adb "$HOME/Library/Android/sdk/platform-tools/adb"; do
    if [ -x "$CANDIDATE" ]; then
        mkdir -p "$HELPERS_DIR"
        cp "$(readlink -f "$CANDIDATE" 2>/dev/null || echo "$CANDIDATE")" "$HELPERS_DIR/adb"
        # Nested code signs first; sealing the bundle afterwards covers it.
        # adb arrives signed by Google, which notarization rejects inside
        # someone else's app, so this replaces that signature rather than
        # adding to it.
        codesign --force "${SIGN_ARGS[@]}" "$HELPERS_DIR/adb"
        echo "Bundled adb from $CANDIDATE ($(du -h "$HELPERS_DIR/adb" | cut -f1))."
        break
    fi
done
[ -d "$HELPERS_DIR" ] || echo "No adb found to bundle; Android capture will look for one at runtime."

# Seal the whole bundle, nested code included.
codesign --force "${SIGN_ARGS[@]}" "${APP_SIGN_ARGS[@]}" "$APP_DIR"

echo "Build complete! $APP_DIR $VERSION ($(lipo -archs "$MACOS_DIR/$APP_NAME"), macOS $MIN_MACOS+)"
