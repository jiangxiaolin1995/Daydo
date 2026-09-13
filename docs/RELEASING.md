# 发布 Daydo

此文档记录可重复执行的构建与发布命令；产品范围和本次验收结论统一记录在 [PLAN.md](PLAN.md)。

## 分发前提

- 使用 Developer ID Application 签名，主应用与小组件都保留各自的 App Group、CloudKit 权限。
- 使用 Developer ID 分发描述文件；包含 `ProvisionedDevices` 的开发描述文件不能用于公开下载。
- Release 使用 CloudKit Production、生产推送权限，无 `get-task-allow`。
- Apple 公证通过并装订票据；不以关闭 Gatekeeper 或去掉权限绕过分发条件。
- 凭据保留在本机 Keychain；不要把私钥、证书、描述文件、任务数据库或运行日志提交到 Git。

参考：[Apple Developer ID](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)、[Apple 公证流程](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

## 构建与导出

先运行 `swift test --jobs 4`。避免同时启动其他 Xcode 构建。

```sh
xcodegen generate
xcodebuild -project Daydo.xcodeproj -scheme Daydo -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/Daydo-todo" \
  -archivePath "$PWD/release/Daydo.xcarchive" \
  -jobs 4 -skipPackageUpdates -allowProvisioningUpdates \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO DAYDO_APS_ENVIRONMENT=development archive

xcodebuild -exportArchive -archivePath "$PWD/release/Daydo.xcarchive" \
  -exportPath "$PWD/release/export" \
  -exportOptionsPlist Configuration/ExportOptions.plist -allowProvisioningUpdates
```

归档暂用开发证书和开发推送权限；Xcode 在 Developer ID 导出阶段重新签名并转换为分发权限。
不能直接把 `.xcarchive/Products/Applications/Daydo.app` 上传给用户。若导出失败，应修复证书或描述文件后重试。

导出后检查主应用与小组件的实际签名、权限、架构和描述文件；确认不含 `get-task-allow`，
CloudKit 为 Production，主应用推送为 production。`lipo -archs` 应包含 arm64 和 x86_64。
检查包内包含 `THIRD_PARTY_NOTICES.txt`，并运行 `script/check_widget_intent.py`。

## 公证与 DMG

先通过 Apple 官方流程在本机 Keychain 配置 notarytool 凭据，把对应 profile 名称放入
`DAYDO_NOTARY_PROFILE` 环境变量。不要把密码、私钥或凭据写进命令记录和仓库。

```sh
ditto -c -k --keepParent release/export/Daydo.app release/Daydo-notarization.zip
xcrun notarytool submit release/Daydo-notarization.zip \
  --keychain-profile "$DAYDO_NOTARY_PROFILE" --wait
xcrun stapler staple release/export/Daydo.app
xcrun stapler validate release/export/Daydo.app
spctl --assess --type execute --verbose=2 release/export/Daydo.app

./script/package_dmg.sh "$PWD/release/export/Daydo.app" "$PWD/release/Daydo-1.0.0-universal.dmg"
xcrun notarytool submit release/Daydo-1.0.0-universal.dmg \
  --keychain-profile "$DAYDO_NOTARY_PROFILE" --wait
xcrun stapler staple release/Daydo-1.0.0-universal.dmg
xcrun stapler validate release/Daydo-1.0.0-universal.dmg
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
