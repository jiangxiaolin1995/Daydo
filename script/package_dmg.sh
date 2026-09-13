#!/usr/bin/env bash
# Package an exported, notarized Daydo app. Never publish a development-signed bundle.
set -euo pipefail
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 /absolute/path/Daydo.app /absolute/path/Daydo-version-universal.dmg" >&2
  exit 2
fi
DAYDO_RELEASE_APP="$1"
DAYDO_RELEASE_DMG="$2"
[ -d "$DAYDO_RELEASE_APP" ] || { echo "Application not found." >&2; exit 1; }
[ ! -e "$DAYDO_RELEASE_DMG" ] || { echo "Output already exists; choose a new path." >&2; exit 1; }
DAYDO_RELEASE_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DAYDO_RELEASE_APP/Contents/Info.plist")
[ "$DAYDO_RELEASE_ID" = "com.xiaolin.daydo" ] || { echo "Expected Daydo.app." >&2; exit 1; }
codesign --verify --deep --strict "$DAYDO_RELEASE_APP"
DAYDO_RELEASE_SIGNING=$(codesign -dvv "$DAYDO_RELEASE_APP" 2>&1)
case "$DAYDO_RELEASE_SIGNING" in
  *"Authority=Developer ID Application:"*) ;;
  *) echo "Public DMG requires a Developer ID Application signature; development/ad hoc signing is not accepted." >&2; exit 1 ;;
esac
xcrun stapler validate "$DAYDO_RELEASE_APP"
spctl --assess --type execute --verbose=2 "$DAYDO_RELEASE_APP"
DAYDO_RELEASE_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/daydo-dmg.XXXXXX")
trap 'rm -rf "$DAYDO_RELEASE_STAGE"' EXIT
ditto --noextattr --norsrc "$DAYDO_RELEASE_APP" "$DAYDO_RELEASE_STAGE/Daydo.app"
ln -s /Applications "$DAYDO_RELEASE_STAGE/Applications"
cat > "$DAYDO_RELEASE_STAGE/安装说明.txt" <<'DAYDO_INSTALL'
Daydo

把 Daydo.app 拖到 Applications，然后从「应用程序」打开。
首次启动后，可在设置中配置通知、Agent MCP 和备份。
桌面右键 → 编辑小组件 → 搜索 Daydo，即可添加小组件。

版本说明与已知限制：https://github.com/jiangxiaolin1995/Daydo/releases
DAYDO_INSTALL
mkdir -p "$(dirname "$DAYDO_RELEASE_DMG")"
hdiutil create -volname Daydo -srcfolder "$DAYDO_RELEASE_STAGE" -format UDZO "$DAYDO_RELEASE_DMG"
hdiutil verify "$DAYDO_RELEASE_DMG"
echo "DMG created: $DAYDO_RELEASE_DMG"
echo "Submit and staple this DMG before attaching it to a public GitHub Release."
