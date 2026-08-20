#!/bin/bash
# Builds AgentCapabilityManager.app.
#
# The scratch path deliberately lives outside this directory: Desktop is iCloud-synced here, and
# the com.apple.FinderInfo xattr it adds makes `codesign` refuse the build products.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRATCH="${ACM_SCRATCH:-${TMPDIR:-/tmp}/acm-build}"
# Stage and sign in the scratch area, then copy the finished bundle out. Signing directly inside
# an iCloud-synced folder fails: the fileprovider re-adds com.apple.FinderInfo between the xattr
# strip and codesign, and codesign rejects it.
STAGE="$SCRATCH/AgentCapabilityManager.app"
APP="${ACM_OUTPUT:-$ROOT/AgentCapabilityManager.app}"

swift build -c release --scratch-path "$SCRATCH"
BIN="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)/AgentCapabilityManager"

rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN" "$STAGE/Contents/MacOS/AgentCapabilityManager"

if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
  python3 "$ROOT/scripts/make_icon.py"
fi
cp "$ROOT/Resources/AppIcon.icns" "$STAGE/Contents/Resources/AppIcon.icns"

cat > "$STAGE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Agent Capabilities</string>
  <key>CFBundleDisplayName</key><string>Agent Capabilities</string>
  <key>CFBundleExecutable</key><string>AgentCapabilityManager</string>
  <key>CFBundleIdentifier</key><string>local.agentcapabilities.manager</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
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
