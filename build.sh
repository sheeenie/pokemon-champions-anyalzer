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

# Ad-hoc sign the whole bundle so its contents are sealed together. Apple
# Silicon won't run unsigned code, and macOS only offers "Open Anyway" for a
# downloaded app that is signed. This isn't a Developer ID signature, so it
# doesn't avoid that prompt.
codesign --force --sign - "$APP_DIR"

echo "Build complete! $APP_DIR $VERSION ($(lipo -archs "$MACOS_DIR/$APP_NAME"), macOS $MIN_MACOS+)"
