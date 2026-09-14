#!/bin/bash
set -e

APP_NAME="iPhoneMirror"
APP_DIR="$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

# Create directories. Resources are linked into the executable (below), so the
# bundle has no Resources folder; remove one left by an older build.
mkdir -p "$MACOS_DIR"
rm -rf "$RESOURCES_DIR"

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.$APP_NAME</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
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
swiftc -O -parse-as-library \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __resources -Xlinker "$BLOB" \
    main.swift \
    CaptureManager.swift \
    CameraPreview.swift \
    BattleGeometry.swift \
    BattleAnalyzer.swift \
    BattleState.swift \
    IconMatcher.swift \
    PokedexStore.swift \
    StatsPanel.swift \
    TypeChart.swift \
    TypeIcons.swift \
    Localization.swift \
    EmbeddedResources.swift \
    -o "$MACOS_DIR/$APP_NAME"

echo "Build complete! App bundle created at: $APP_DIR"
