#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
APP="$PWD/.build/package.noindex/Cherry Keys for Mac.app"
[[ -d "$APP" ]] || { print -u2 'Run scripts/build.sh first.'; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
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
cat > "$PAYLOAD/Start Here.txt" <<'TEXT'
Cherry Keys for Mac

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

This is a locally signed development build, not an Apple Developer ID
notarized release. A DMG is packaging, not a change in trust or permissions.
Do not disable Gatekeeper, SIP, signature checks or macOS privacy controls.
Public release requires a protected signing/notarization workflow.

Independent community software, not affiliated with CHERRY. MIT licensed.
TEXT
hdiutil create -quiet -ov -format UDZO -fs HFS+ -volname 'Cherry Keys for Mac' \
    -srcfolder "$PAYLOAD" "$STAGE/output.dmg"
# Generate outside dist first; preserve any previous output if creation fails.
hdiutil verify -quiet "$STAGE/output.dmg"
mv -f "$STAGE/output.dmg" "dist/app/$IMAGE_NAME"
(cd dist/app && shasum -a 256 "$IMAGE_NAME" > SHA256SUMS)
print "Packaged dist/app/$IMAGE_NAME"
