#!/bin/bash
# Builds Skillswitch.app.
#
# The scratch path deliberately lives outside this directory: Desktop is iCloud-synced here, and
# the com.apple.FinderInfo xattr it adds makes `codesign` refuse the build products.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRATCH="${SKILLSWITCH_SCRATCH:-${TMPDIR:-/tmp}/skillswitch-build}"
# Stage and sign in the scratch area, then copy the finished bundle out. Signing directly inside
# an iCloud-synced folder fails: the fileprovider re-adds com.apple.FinderInfo between the xattr
# strip and codesign, and codesign rejects it.
STAGE="$SCRATCH/Skillswitch.app"
APP="${SKILLSWITCH_OUTPUT:-$ROOT/Skillswitch.app}"

swift build -c release --scratch-path "$SCRATCH"
BIN="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)/Skillswitch"

rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN" "$STAGE/Contents/MacOS/Skillswitch"

if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
  python3 "$ROOT/scripts/make_icon.py"
fi
cp "$ROOT/Resources/AppIcon.icns" "$STAGE/Contents/Resources/AppIcon.icns"

cat > "$STAGE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Skillswitch</string>
  <key>CFBundleDisplayName</key><string>Skillswitch</string>
  <key>CFBundleExecutable</key><string>Skillswitch</string>
  <key>CFBundleIdentifier</key><string>dev.skillswitch.Skillswitch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHumanReadableCopyright</key><string>Local capability control panel. No network access.</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <!-- Menu bar utility: no Dock icon. The desktop panel switches the activation policy to
       regular while it is open (see PanelPresenter) so it can take focus normally. -->
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><true/>
</dict>
</plist>
PLIST

xattr -cr "$STAGE" 2>/dev/null || true
codesign --force --sign - "$STAGE"

rm -rf "$APP"
mkdir -p "$(dirname "$APP")"
ditto "$STAGE" "$APP"
codesign --verify --deep "$APP" && echo "Built and verified $APP"
