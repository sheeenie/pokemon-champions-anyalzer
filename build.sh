#!/bin/bash
set -e

APP_NAME="iPhoneMirror"
APP_DIR="$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

# Create directories
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

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

# Compile the swift files into an executable
swiftc -parse-as-library \
    main.swift \
    CaptureManager.swift \
    CameraPreview.swift \
    BattleGeometry.swift \
    BattleAnalyzer.swift \
    -o "$MACOS_DIR/$APP_NAME"

echo "Build complete! App bundle created at: $APP_DIR"
