# 发布 Daydo

此文档记录可重复执行的构建与发布命令；产品范围和本次验收结论统一记录在 [PLAN.md](PLAN.md)。

## 分发前提

- 使用 Developer ID Application 签名，主应用与小组件都保留各自的 App Group、CloudKit 权限。
  可使用本机证书，或由已登录 Xcode 的团队使用云管理证书；本机 `security find-identity`
  没有列出 Developer ID 不代表云签名不可用，以导出结果和实际签名为准。
- 使用 Developer ID 分发描述文件；包含 `ProvisionedDevices` 的开发描述文件不能用于公开下载。
- Release 使用 CloudKit Production、生产推送权限，无 `get-task-allow`。
- Apple 公证通过并装订票据；不以关闭 Gatekeeper 或去掉权限绕过分发条件。
- 凭据保留在本机 Keychain；不要把私钥、证书、描述文件、任务数据库或运行日志提交到 Git。

参考：[Apple Developer ID](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)、[Apple 公证流程](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

## 构建与导出

先运行 `swift test --jobs 4`。避免同时启动其他 Xcode 构建。发行目录放在本机 Library 中，
不要放入 iCloud 管理的 Desktop 或 Documents：文件提供程序附加的 FinderInfo 可能导致
签名校验失败。以下步骤使用同一个终端，并为新版本选择尚未使用的发行目录。

```sh
DAYDO_RELEASE_ROOT="$HOME/Library/Developer/Xcode/DaydoRelease/1.0.0-beta.1"
mkdir -p "$DAYDO_RELEASE_ROOT"
xcodegen generate
xcodebuild -project Daydo.xcodeproj -scheme Daydo -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/Daydo-todo" \
  -archivePath "$DAYDO_RELEASE_ROOT/Daydo.xcarchive" \
  -jobs 4 -skipPackageUpdates -allowProvisioningUpdates \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO DAYDO_APS_ENVIRONMENT=development archive

xcodebuild -exportArchive -archivePath "$DAYDO_RELEASE_ROOT/Daydo.xcarchive" \
  -exportPath "$DAYDO_RELEASE_ROOT/export" \
  -exportOptionsPlist Configuration/ExportOptions.plist -allowProvisioningUpdates
```

归档暂用开发证书和开发推送权限；Xcode 在 Developer ID 导出阶段重新签名并转换为分发权限。
不能直接把 `.xcarchive/Products/Applications/Daydo.app` 上传给用户。若导出失败，应修复证书或描述文件后重试。

导出后检查主应用与小组件的实际签名、权限、架构和描述文件；确认不含 `get-task-allow`，
CloudKit 为 Production，主应用推送为 production。`lipo -archs` 应包含 arm64 和 x86_64。
检查包内包含 `THIRD_PARTY_NOTICES.txt`，并运行 `script/check_widget_intent.py`。

## 公证与 DMG

### 使用已登录的 Xcode 公证应用

Developer ID 的 `destination=upload` 会把应用上传到 Apple 公证服务，不是发布到 Mac App Store。
这条流程复用 Xcode 账户和云管理证书；它不要求把 Apple 密码交给脚本。

```sh
cp Configuration/ExportOptions.plist "$DAYDO_RELEASE_ROOT/NotarizationOptions.plist"
/usr/libexec/PlistBuddy -c 'Set :destination upload' "$DAYDO_RELEASE_ROOT/NotarizationOptions.plist"
xcodebuild -exportArchive -archivePath "$DAYDO_RELEASE_ROOT/Daydo.xcarchive" \
  -exportOptionsPlist "$DAYDO_RELEASE_ROOT/NotarizationOptions.plist" -allowProvisioningUpdates

# 上传完成后，等待 Apple 处理完成，再导出带公证票据的应用。
xcodebuild -exportNotarizedApp -archivePath "$DAYDO_RELEASE_ROOT/Daydo.xcarchive" \
  -exportPath "$DAYDO_RELEASE_ROOT/notarized"
codesign --verify --deep --strict "$DAYDO_RELEASE_ROOT/notarized/Daydo.app"
xcrun stapler validate "$DAYDO_RELEASE_ROOT/notarized/Daydo.app"
spctl --assess --type execute --verbose=2 "$DAYDO_RELEASE_ROOT/notarized/Daydo.app"
```

上传成功不代表公证完成。若仍在处理，应等待同一次提交，不要重新上传相同版本。

### 打包并公证 DMG

先在本机 Keychain 配置 notarytool 凭据，设置 `DAYDO_NOTARY_PROFILE` 为对应 profile 名称。
可手动运行下面的命令，按提示输入 Apple 账户、团队和应用专用密码：

```sh
xcrun notarytool store-credentials "daydo-notary"
DAYDO_NOTARY_PROFILE="daydo-notary"
```

不要在聊天、命令参数或仓库中写密码、私钥和令牌。Xcode 账户登录与 notarytool 的 Keychain
profile 是两套配置；前一项完成不会自动创建后一项。
应用专用密码应在 account.apple.com 使用同一个开发者 Apple 账户生成；终端需要输入网页
生成的应用专用密码。`store-credentials` 验证和保存成功后，才继续提交公证。

```sh
DAYDO_RELEASE_DMG="$DAYDO_RELEASE_ROOT/Daydo-1.0.0-beta.1-universal.dmg"
./script/package_dmg.sh "$DAYDO_RELEASE_ROOT/notarized/Daydo.app" "$DAYDO_RELEASE_DMG"
xcrun notarytool submit "$DAYDO_RELEASE_DMG" \
  --keychain-profile "$DAYDO_NOTARY_PROFILE" --wait
xcrun stapler staple "$DAYDO_RELEASE_DMG"
xcrun stapler validate "$DAYDO_RELEASE_DMG"
```

`package_dmg.sh` 会拒绝开发签名、未公证应用以及已存在的输出文件。票据装订完成后再计算 SHA-256。

## GitHub Release

1. 核对待提交文件，确认没有本机数据、凭据或日志；更新 README 的分发状态和已知限制。
2. 提交并推送源码，核对远程提交与本地一致。
3. 挂载 DMG 验证应用、Applications 链接、签名与票据；卸载本次挂载卷。
4. 为已验证提交创建 tag，创建 Release，上传 DMG 与 SHA256SUMS.txt。
5. 从 GitHub 下载实际附件，再核对 SHA-256 与 DMG 完整性，确认 Release 为公开可访问。

有尚未完成的功能或设备验收时，发布为预览版并写明限制。签名或公证未完成时，保留草稿，
不要把仅能在开发设备运行的包标为通用安装包。
