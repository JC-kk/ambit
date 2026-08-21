#!/bin/bash
# Packages a release: dist/Skillswitch-<version>.dmg, .zip and checksums.txt.
#
# The staging copy comes from the scratch build, never from the working copy. On an iCloud-synced
# folder the fileprovider re-adds com.apple.FinderInfo to anything sitting there, and an app carrying
# that xattr fails `codesign --verify` after packaging — which is exactly the kind of thing that
# looks like a broken download to whoever grabs the dmg.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' \
  "$ROOT/Skillswitch.app/Contents/Info.plist" 2>/dev/null || echo dev)}"
SCRATCH="${SKILLSWITCH_SCRATCH:-${TMPDIR:-/tmp}/skillswitch-build}"
DIST="$ROOT/dist"
STAGE="$SCRATCH/package"

"$ROOT/build.sh"

SOURCE="$SCRATCH/Skillswitch.app"
[ -d "$SOURCE" ] || SOURCE="$ROOT/Skillswitch.app"

rm -rf "$STAGE" && mkdir -p "$STAGE/dmg"
ditto "$SOURCE" "$STAGE/dmg/Skillswitch.app"
xattr -cr "$STAGE/dmg/Skillswitch.app"
codesign --verify --deep --strict "$STAGE/dmg/Skillswitch.app"
ln -s /Applications "$STAGE/dmg/Applications"

rm -rf "$DIST" && mkdir -p "$DIST"
hdiutil create -volname "Skillswitch" -srcfolder "$STAGE/dmg" -ov -format UDZO \
  -quiet "$DIST/Skillswitch-$VERSION.dmg"
ditto -c -k --keepParent "$STAGE/dmg/Skillswitch.app" "$DIST/Skillswitch-$VERSION.zip"

cd "$DIST"
shasum -a 256 "Skillswitch-$VERSION.dmg" "Skillswitch-$VERSION.zip" > checksums.txt

echo "Packaged Skillswitch $VERSION:"
ls -lh "$DIST"
echo
cat checksums.txt
