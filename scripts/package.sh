#!/bin/bash
# Packages a release: dist/Ambit-<version>.dmg, .zip and checksums.txt.
#
# The staging copy comes from the scratch build, never from the working copy. On an iCloud-synced
# folder the fileprovider re-adds com.apple.FinderInfo to anything sitting there, and an app carrying
# that xattr fails `codesign --verify` after packaging — which is exactly the kind of thing that
# looks like a broken download to whoever grabs the dmg.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' \
  "$ROOT/Ambit.app/Contents/Info.plist" 2>/dev/null || echo dev)}"
SCRATCH="${AMBIT_SCRATCH:-${TMPDIR:-/tmp}/ambit-build}"
DIST="$ROOT/dist"
STAGE="$SCRATCH/package"

"$ROOT/build.sh"

SOURCE="$SCRATCH/Ambit.app"
[ -d "$SOURCE" ] || SOURCE="$ROOT/Ambit.app"

rm -rf "$STAGE" && mkdir -p "$STAGE/dmg"
ditto "$SOURCE" "$STAGE/dmg/Ambit.app"
xattr -cr "$STAGE/dmg/Ambit.app"
codesign --verify --deep --strict "$STAGE/dmg/Ambit.app"
ln -s /Applications "$STAGE/dmg/Applications"

rm -rf "$DIST" && mkdir -p "$DIST"
hdiutil create -volname "Ambit" -srcfolder "$STAGE/dmg" -ov -format UDZO \
  -quiet "$DIST/Ambit-$VERSION.dmg"
ditto -c -k --keepParent "$STAGE/dmg/Ambit.app" "$DIST/Ambit-$VERSION.zip"

cd "$DIST"
shasum -a 256 "Ambit-$VERSION.dmg" "Ambit-$VERSION.zip" > checksums.txt

echo "Packaged Ambit $VERSION:"
ls -lh "$DIST"
echo
cat checksums.txt
