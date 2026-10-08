#!/bin/bash
set -e

APP_NAME="OllamaChat"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Building ${APP_NAME}..."

# Check if Xcode is installed and active
DEVELOPER_DIR=$(xcode-select -p)
if [[ "$DEVELOPER_DIR" == *"/CommandLineTools"* ]] && [ ! -d "/Applications/Xcode.app" ]; then
    echo ""
    echo "⚠️  NOTE: You currently have Apple Command Line Tools active ($DEVELOPER_DIR)."
    echo "SwiftUI and SwiftData macros in Swift 6 require full Xcode to compile."
    echo "Please install Xcode from the Mac App Store: https://apps.apple.com/app/xcode/id497799835"
    echo "Then run:"
    echo "   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    echo "   ./build_app.sh"
    echo ""
    echo "Alternatively, open the project directly in Xcode:"
    echo "   open Package.swift"
    exit 1
fi

# Build release executable using swift package manager
echo "==> Compiling native release binary..."
swift build -c release

RELEASE_BIN="${PROJECT_DIR}/.build/arm64-apple-macosx/release/${APP_NAME}"
if [ ! -f "$RELEASE_BIN" ]; then
    RELEASE_BIN="${PROJECT_DIR}/.build/release/${APP_NAME}"
fi

if [ ! -f "$RELEASE_BIN" ]; then
    echo "❌ Error: Could not locate compiled binary at $RELEASE_BIN"
    exit 1
fi

echo "==> Packaging ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy binary
cp "$RELEASE_BIN" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Generate Info.plist
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>OllamaChat</string>
    <key>CFBundleIdentifier</key>
    <string>com.faltucode.OllamaChat</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>OllamaChat</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# Sign with entitlements
if [ -f "${PROJECT_DIR}/OllamaChat.entitlements" ]; then
    echo "==> Signing app with entitlements..."
    codesign --force --deep --sign - --entitlements "${PROJECT_DIR}/OllamaChat.entitlements" "${APP_BUNDLE}"
fi

# Install to /Applications
INSTALL_PATH="/Applications/${APP_BUNDLE}"
echo "==> Installing to ${INSTALL_PATH}..."
rm -rf "${INSTALL_PATH}"
cp -R "${APP_BUNDLE}" "${INSTALL_PATH}"

echo "✅ Successfully installed ${APP_NAME} to /Applications!"
echo "==> Launching ${APP_NAME}..."
open "${INSTALL_PATH}"
