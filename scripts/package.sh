#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
APP="$PWD/.build/package.noindex/Cherry Keys for Mac.app"
[[ -d "$APP" ]] || { print -u2 'Run scripts/build.sh first.'; exit 1; }
python3 scripts/check-release.py --app "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'Invalid app version.'; exit 1; }
IMAGE_NAME="CherryKeysMac-$VERSION-macOS-universal.dmg"
mkdir -p dist/app .build/dmg.noindex
STAGE=$(mktemp -d "$PWD/.build/dmg.noindex/stage.XXXXXXXX")
trap 'rm -rf "$STAGE"' EXIT
PAYLOAD="$STAGE/payload"
mkdir "$PAYLOAD"
codesign --verify --deep --strict "$APP"
# Copy bundle contents without carrying local Finder/quarantine metadata.
ditto --norsrc --noextattr "$APP" "$PAYLOAD/Cherry Keys for Mac.app"
codesign --verify --deep --strict "$PAYLOAD/Cherry Keys for Mac.app"
ln -s /Applications "$PAYLOAD/Applications"
cp LICENSE "$PAYLOAD/LICENSE.txt"
cp CHANGELOG.md "$PAYLOAD/Changelog.md"
{
print -r -- "Cherry Keys for Mac $VERSION (build $BUILD)"
cat <<'TEXT'

1. Quit any existing Cherry Keys for Mac installation before replacing it.
   If upgrading the privileged broker, remove the helper in the old app first.
2. Drag Cherry Keys for Mac.app onto the Applications shortcut.
3. Eject this disk image. Open the app from Applications, not from this image.
4. Allow the installed app in System Settings > Privacy & Security >
   Accessibility AND Input Monitoring. Quit and reopen it afterward.
5. Choose Set up helper and complete any macOS Login Items & Extensions
   approval. Then select your profile and choose Enable remapping.

Pause and Enable do not normally require another administrator password.
Existing profiles are preserved. Each app launch starts paused.

KW X ULP: with the Fn light off, preset F8/F11/F12 provide Browser Home,
Calculator and Mail. Hold Fn for the independent standard F-key layer.
Ctrl+Fn reverses these layers. Choose the named preset trigger to replace
its command; choose Fn + F12 (standard F12) to map the other layer.
Browser Home sends Command-Shift-H to the foreground app; behavior varies.

This is a locally signed development build, not an Apple Developer ID
notarized release. A DMG is packaging, not a change in trust or permissions.
Do not disable Gatekeeper, SIP, signature checks or macOS privacy controls.
Production distribution still needs protected signing and notarization.

Independent community software, not affiliated with CHERRY. MIT licensed.
TEXT
} > "$PAYLOAD/Start Here.txt"
hdiutil create -quiet -ov -format UDZO -fs HFS+ -volname 'Cherry Keys for Mac' \
    -srcfolder "$PAYLOAD" "$STAGE/output.dmg"
# Generate outside dist first; preserve any previous output if creation fails.
hdiutil verify -quiet "$STAGE/output.dmg"
mv -f "$STAGE/output.dmg" "dist/app/$IMAGE_NAME"
(cd dist/app && shasum -a 256 "$IMAGE_NAME" > SHA256SUMS)
print "Packaged dist/app/$IMAGE_NAME"
