#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Staging is excluded from Spotlight; installation creates the one searchable app.
APP="$PWD/.build/package.noindex/Cherry Keys for Mac.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build
mkdir -p "$APP/Contents/Library/LaunchDaemons"
GUI_ONLY=${CHERRY_GUI_ONLY:-0}
SDK="$(xcrun --sdk macosx --show-sdk-path)"
for ARCH in arm64 x86_64; do
    if [[ "$GUI_ONLY" != 1 ]]; then
    swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macosx13.0" -framework IOKit -framework SystemConfiguration Sources/Shared/CherryDeviceIdentity.swift Sources/HIDCapture/*.swift -o ".build/CherryKeysHIDCapture-$ARCH"
    swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macosx13.0" -framework Security -framework SystemConfiguration Sources/Shared/*.swift Sources/CaptureService/*.swift -o ".build/CherryKeysCaptureService-$ARCH"
    fi
    swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macosx13.0" -framework SwiftUI -framework AppKit -framework ApplicationServices -framework IOKit -framework Carbon -framework ServiceManagement -framework Security Sources/Shared/*.swift Sources/CherryKeysMac/*.swift -o ".build/CherryKeysMac-$ARCH"
done
lipo -create .build/CherryKeysMac-arm64 .build/CherryKeysMac-x86_64 -output "$APP/Contents/MacOS/CherryKeysMac"
if [[ "$GUI_ONLY" != 1 ]]; then
lipo -create .build/CherryKeysHIDCapture-arm64 .build/CherryKeysHIDCapture-x86_64 -output "$APP/Contents/MacOS/CherryKeysHIDCapture"
lipo -create .build/CherryKeysCaptureService-arm64 .build/CherryKeysCaptureService-x86_64 -output "$APP/Contents/MacOS/CherryKeysCaptureService"
python3 scripts/sign-local.py local.cherrykeys.mac.capture "$APP/Contents/MacOS/CherryKeysHIDCapture"
python3 scripts/sign-local.py local.cherrykeys.mac.capture-service "$APP/Contents/MacOS/CherryKeysCaptureService"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/local.cherrykeys.mac.capture-service.plist "$APP/Contents/Library/LaunchDaemons/"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi
python3 scripts/sign-local.py local.cherrykeys.mac "$APP"
codesign --verify --deep --strict "$APP"
print "Built $APP"
