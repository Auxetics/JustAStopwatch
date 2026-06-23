#!/bin/bash
set -e

VERSION=${1:-"1.0"}
echo "Building JustAStopwatch version $VERSION..."

echo "Compiling Swift Source..."
mkdir -p "JustAStopwatch.app/Contents/MacOS"
swiftc -target arm64-apple-macos13.0 Source/main.swift -o "JustAStopwatch.app/Contents/MacOS/JustAStopwatch"

echo "Creating PkgInfo..."
echo -n "APPL????" > "JustAStopwatch.app/Contents/PkgInfo"

echo "Creating Info.plist..."
cat <<EOF > "JustAStopwatch.app/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>JustAStopwatch</string>
    <key>CFBundleIdentifier</key>
    <string>com.auxetics.justastopwatch</string>
    <key>CFBundleName</key>
    <string>JustAStopwatch</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "Codesigning..."
codesign --force --deep -s - "JustAStopwatch.app"

echo "Creating DMG Installer..."
rm -rf build_dmg JustAStopwatch.dmg
mkdir -p build_dmg
cp -R "JustAStopwatch.app" build_dmg/
ln -s /Applications build_dmg/Applications
hdiutil create -volname "JustAStopwatch" -srcfolder build_dmg -ov -format UDZO "JustAStopwatch.dmg"

echo "Build Complete! JustAStopwatch.dmg is ready."
