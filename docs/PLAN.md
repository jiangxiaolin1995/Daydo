# Daydo 实施与验收

## 当前产品约定

用户在 2026-09-14 明确调整为：**Daydo 免登录使用，可通过系统 iCloud 同步**。
这替代此前首次必须 Apple 登录的约定。应用启动直接打开任务，MCP、小组件与提醒
均不依赖 Daydo 登录凭据；保留已有任务、系统账户的数据空间隔离和本机离线使用。

macOS 14+，SwiftUI 原生侧栏与系统字体，参考 HeroUI 的蓝色、圆角和层次。
包含多清单、任务详情、重复实例、系统提醒、日周月日历、标准 stdio MCP、三种尺寸
的交互小组件、版本化 JSON 备份及蓝色日历勾选图标。允许关窗后后台运行，可开机启动。
菜单栏使用直径 16pt（2x Retina 为 32px）的原生单色实心圆对号模板图。
关闭最后一个窗口后隐藏 Dock 图标，进程继续运行；
重新打开主窗口或设置时恢复 Dock 入口，最小化保留 Dock 入口。

## 架构与接口

- XcodeGen 管理应用和 Widget Extension；本地 Swift Package 包含共享业务 DaydoCore
  和仅主应用使用的 AppKit 窗口桥接 DaydoDesktop。
- Core Data SQLite 位于 App Group，主进程使用 NSPersistentCloudKitContainer。
- 持久历史、跨进程通知、文件锁、稳定 ID、乐观版本检查与创建请求去重。
- 重复任务按系列与原发生日期标识，完成和单次编辑独立记录。编辑以后分割系列，保留过去。
- 日期采用 Gregorian YYYY-MM-DD，任务带 IANA 时区。周一为首日，时间吸附 15 分钟，默认 30 分钟。
- MCP：get_status、list_lists、create_list、update_list、list_tasks、get_task、
  create_task、update_task、set_task_completion。get_status 返回 ready、signInRequired=false。
- 官方 MCP SDK 固定 0.12.1，NIO 2.86.0、Collections 1.2.1、Atomics 1.3.0。
  SDK 的 experimental 解码限制由窄范围初始化适配器处理，工具参数与标准 stdio 不改写。
- Widget Provider 和完成 Intent 均检查当前系统账户；账户变化时不继续读取旧数据空间。
- JSON schemaVersion=1，导入先预览，稳定 ID 去重并保留已有编辑，校验实例和清单引用。

## 当前证据

- 2026-09-14 菜单栏图标先改为 `checkmark.circle.fill`，尝试将 SwiftUI frame 调为
  18pt、22pt。用户连续截图确认两次圆形墨迹都只有 26px，右侧参考图标为 32px；
  这些 frame 修改未改变实际菜单栏图标尺寸，不能用编译和安装成功代替尺寸验收。
  现改用 `MenuBarIcon.image` 原生绘制 16pt 圆形与镂空对号，使用模板模式跟随菜单栏颜色。
  安装版 `NSStatusBarButton` 日志确认实际 image 和绘制区域均为 16×16pt，backing=2，
  即 32×32px。证据见 `artifacts/menu-bar-native-geometry.log`。Debug 启动仅记录一次
  不含用户数据的图标尺寸日志，Release 不包含此诊断。
  `WindowPresentationController` 监听原生窗口关闭及激活通知，排除菜单栏临时窗口和
  已关闭但仍被 SwiftUI 保留的窗口；设置未关或主窗口最小化时保留 Dock 入口。
  保持单实例主窗口及不退出进程的约定，菜单、外部链接和应用再次打开时恢复前台模式。
- 本次新增 7 项窗口回归测试，先复现失败，再通过全部 45 项测试。真实安装版点击红色
  关闭按钮后，Launch Services 的同一 GUI PID 从 `Foreground` 变为 `UIElement`；
  重新打开恢复 `Foreground` 和同一个 `main` 窗口，最小化保留 `Foreground`。
  实测独立设置窗口可打开，设置仍开着时关闭主窗口不会隐藏 Dock。
- 同时修复 MCP 仅识别 `.regular` 协调进程的问题，`.accessory` 后台进程也视为已运行。
  真实 stdio 写入回归先在旧逻辑复现 Dock 被重新唤起，修复后创建清单、任务、编辑、
  完成、重试和归档全程保持同一后台 GUI PID；测试清单已归档，测试客户端均随 EOF 退出。
  证据为 `artifacts/mcp-dock-red.json`、`artifacts/mcp-dock-green.json` 和
  `artifacts/window-presentation-verification.json`；`script/check_mcp.py --exercise
  --background-pid <GUI_PID>` 可在手动关闭所有窗口后重复执行。
  小组件和应用的完成 Intent 元数据仍通过后台模式校验。本次未重复操作真实桌面任务。
  已安装到 `~/Applications/Daydo.app`，已有 MCP 连接需要重连才能加载新版服务端。
  此变更纳入 1.0.0 Beta 2（build 2）发布；保留已发布的 Beta 1 安装包。
- 本机 macOS 26.6.2、Xcode 26.6、Swift 6.3.3；完整应用与小组件已构建和签名。
- 开发团队 2S5P3UNGAL；App ID com.xiaolin.daydo，Widget com.xiaolin.daydo.widget。
- App Group 2S5P3UNGAL.com.xiaolin.daydo；CloudKit iCloud.com.xiaolin.daydo。
  Debug 明确使用 Development，Release 使用 Production。
- 38 项核心测试通过。包含重复历史、跨年、DST、日期边界、软删除恢复、并发去重、
  版本冲突、参数校验、备份、持久历史、Codex 初始化兼容、免登录操作及账户隔离。
  冷启动会先确认已有云数据空间的当前账户；全新本机使用不等待网络。
  关键变更保留了先失败后通过的回归记录。
- 已安装免登录版本并在真实窗口确认启动直接进入任务，原有任务保留。应用和小组件的
  实际签名不再包含 Apple 登录或共享 Keychain 权限，源码不再读取旧登录凭据。
  最终安装版与 dist 二进制一致，正常 Run 的 --verify 入口通过；预览测试进程已结束。
  证据见 artifacts/final-install-verification.json、artifacts/mcp-final-installed.json。
- 真实应用已验证任务新建、编辑、清单创建、重启保留数据和 Command-N。
  独立演示数据验证 Command-Return 完成、Command-Z 撤销、Command-F 聚焦与全局搜索。
  撤销状态的观察通知遗漏已根据真实失败修复，见 artifacts/keyboard-ui-checks.json。
- 已检查浅色任务列表、周历、月历以及深色周历和搜索结果。月历根据格子高度调整可见
  任务数，修复“还有 N 项”挤到下一周的问题；周历的控件标签和全天区布局也已修复。
- Codex 实际客户端已完成查询、新建、编辑、完成、结果核对与归档，证据为
  artifacts/codex-client-approved.jsonl。免登录版本再次通过全部流程，证据为
  artifacts/codex-guest-client.jsonl；标准 stdio 的请求去重、版本冲突、重复完成和 EOF
  退出检查通过，见 artifacts/mcp-guest.json。
- Claude Code 成功连接并识别 9 个工具；模型请求返回 403 Insufficient account balance，
  未完成其模型驱动的操作验收。证据为 artifacts/claude-client.jsonl。
- 用户已确认中号小组件安装，并实际完成了「桌面验收：勾选完成」。MCP 回读确认
  completedAt 存在且 source=widget，证明共享存储完成链路有效。
- 2026-09-14 用户反馈点击小组件会不断打开 Daydo，已在原生窗口菜单复现 3 个主窗口。
  主窗口改为单实例 Window，明确处理 Daydo 外部链接，保留独立设置窗口；普通启动由
  菜单栏入口显式打开主窗口，后台协调进程仍会在无窗口时初始化数据、同步和提醒。
  重新唤起已有窗口后返回 false，避免再次执行系统默认的开窗动作。
- 小组件完成 Intent 移除 ForegroundContinuableIntent，主应用和扩展均声明后台执行。
  安装包中实际提取的 App Intents 元数据从主应用 supportedModes=8、扩展=1，修复为
  两者均为 1（background），openAppWhenRun=false，且均没有前台系统协议。
  回归脚本 script/check_widget_intent.py 在旧产物失败、新安装产物通过；证据为
  artifacts/widget-intent-metadata-red.json 与 widget-intent-metadata-green.json。
- 新增链接路由测试，覆盖今天、新建、重复实例、无效链接，以及重复点击同一标题。
  导航事件可在冷启动后消费；点击“今天”会切回今天，关闭详情后可重新打开同一任务。
- 单窗口版本已在真实界面验证连续三次打开和关窗后重新打开，窗口标识均为 main。
  用户已在桌面实测连续点标题、关窗后勾选，并反馈「正常了」。运行日志显示多次链接
  始终只有一个主窗口；完成操作在 DaydoWidget 进程保存，MCP 回读确认 source=widget、
  completedAt=2026-09-13T17:19:26Z。证据为 artifacts/widget-window-fix-runtime.log、
  widget-window-fix-after.json、widget-window-ui-checks.json；两个验收任务已归档保留。
  桌面控制工具无法定位 Daydo 组件，且浏览器拒绝 daydo:// 自动测试，因此采用用户
  实机操作结合进程日志和数据回读验证，未绕过工具限制。
- 2026-09-14 按用户要求移除主工具栏加号旁重复的 Daydo 名称标签。构建、签名和安装
  通过；真实主窗口截图与辅助功能树确认标签已消失，新建、详情和搜索入口正常显示。
- 2026-09-14 在设置 → Agent 的本地 MCP 配置下方新增「History 自动整理」及一键复制
  提示词、完整内容展开和复制结果反馈。提示词包含每 10 分钟增量总结、明确日期计划的
  优先级安排、去重、稳定请求标识、回读核对与本机 MCP 配置；路径和时区取自当前应用。
  已构建、签名并安装，真实设置窗口确认布局、展开内容以及按钮显示「已复制」。
  此入口仅复制配置提示词，已有的 History 自动任务保持原状。
- CloudKit 账户可用，但读取私有记录区返回 CKErrorDomain 15 / CKInternalErrorDomain 2000，
  Core Data 同步返回 CKErrorDomain 2。未证实云同步成功，不能把本机读写成功当作同步成功。
  免登录版本再次复现，见 artifacts/cloud-diagnostics-guest.json。签名与描述文件中的
  容器、团队和 Development 环境已核对一致，未确认服务器拒绝的根因。
  CloudKit Console 当前还需要网页登录，不能以账户可用推断数据库可访问。
  无第二台 Mac，双机验收未完成。
- imagegen 图标已封装为 Assets/Brand/DaydoIcon-1024.png、Daydo.icns、完整 iconset 与 AppIcon。
  真实应用图标已显示；尚未单独记录 Dock/Finder 的各尺寸验收。

## 待完成的最终验收

### GitHub 公开发布（2026-09-14）

- 用户已授权将菜单栏、关窗和 MCP 后台修复提交到 main、推送 GitHub 并发布新包。
  当前本地与 origin/main 基线一致；Beta 2 使用新 tag `v1.0.0-beta.2`，不覆盖 Beta 1。
  发布前重新测试，重新构建双架构 Release，验证分发签名并分别公证应用与 DMG。
  完成后更新 README 下载链接并验证公开下载的实际附件。
- Beta 2 源码提交 `e65fc7a` 已推送并核对 origin/main 一致；重新运行 45 项测试通过。
  归档和导出均完成，主应用与小组件版本 1.0.0、build 2，均含 arm64 与 x86_64。
  云管理 Developer ID 签名、可信时间戳、hardened runtime、Production CloudKit、
  生产推送及所有设备分发描述文件均通过核对。小组件完成 Intent 仍为后台模式。
- Beta 2 应用 ZIP 公证与 DMG 公证均返回 Accepted，应用和 DMG 均装订票据。
  已只读挂载 DMG，确认 Applications 链接、安装说明、第三方声明、应用签名、公证票据、
  Gatekeeper 和两种架构正确；挂载已卸载。最终 DMG 为 5,900,777 字节，SHA-256 为
  `760fb3afc319d9e7efb1a859a403bb0ac9eaa7306cc68cfb6d04a8346b56dfe7`。
  导出应用的真实 stdio `get_status` 返回 ready=true、signInRequired=false，客户端已退出。
- 用户授权公开源码、编写面向用户的 README，并在 GitHub Releases 提供 DMG。
- 公开仓库已创建：[jiangxiaolin1995/Daydo](https://github.com/jiangxiaolin1995/Daydo)，
  首次源码提交 `f12278d` 已推送到 main，并核对本地、远程提交及 README 内容一致。
  MCP 示例改用 `/Applications`，运行日志、任务数据、
  签名材料和构建产物不进入源码仓库；发行包包含七个 Swift 依赖的许可与声明。
- 重新运行 38 项核心测试，全部通过。Release 归档成功，主应用与小组件均包含 arm64 和
  x86_64，完成 Intent 的后台执行元数据验证通过。Intel Mac 实机验收仍未完成。
- 2026-09-14 用户恢复 Xcode 账户登录后，复用原有归档导出成功。主应用和小组件均使用
  Cloud Managed Developer ID Application 签名，具备 hardened runtime、可信时间戳、
  Production CloudKit／推送权限，无 get-task-allow；分发描述文件允许所有设备，
  不包含注册设备列表。本机没有 Developer ID 私钥不妨碍 Xcode 云签名。
- Desktop 的 iCloud 文件提供程序给导出包附加 FinderInfo，导致严格签名检查失败。
  发行产物移入本机 Library 构建目录，复制时排除资源分支和扩展属性，重新校验通过；
  未删除或重置用户任务、系统账户或 CloudKit 数据。
- 使用 Xcode 已登录账户提交 Apple 公证成功，导出的应用已装订公证票据；stapler validate
  通过，Gatekeeper 返回 accepted / Notarized Developer ID。DMG 已生成（约 5.9 MB），
  只读挂载验证了 Applications 链接、安装说明、内嵌应用签名、公证票据和二进制一致性，
  本次挂载已卸载。应用公证不等于 DMG 文件本身已公证。
- 用户完成 notarytool 的本机 Keychain 配置后，DMG 单独公证返回 Accepted，statusCode=0、
  issues=null；公证票据已装订，stapler validate 通过。已生成最终 SHA-256 校验文件。
- [v1.0.0-beta.1](https://github.com/jiangxiaolin1995/Daydo/releases/tag/v1.0.0-beta.1)
  已于 2026-09-14 公开发布为预览版，包含 `Daydo-1.0.0-beta.1-universal.dmg` 和
  `SHA256SUMS.txt`。tag 指向 `4b05d72`，应用源文件与已验证归档一致，后续变更仅为文档。
- 已使用无 GitHub 登录凭据的请求下载两个公开附件；DMG 为 5,888,219 字节，SHA-256
  与本地最终产物、GitHub 附件 digest 及校验文件一致。下载后的磁盘镜像校验、公证票据、
  只读挂载、内嵌应用签名、公证票据、Gatekeeper、Applications 链接和两种架构均验证通过。
  本次挂载已卸载，发布相关子进程均已结束；README 的直接下载链接与远程内容已核对。
  此验证不替代另一台 Mac、Intel 或 macOS 14 实机验收，也不代表 iCloud 同步已成功。
- 可重复的构建、导出、公证和发布步骤见 [RELEASING.md](RELEASING.md)。

### 应用与设备验收

- 继续实测日历拖动改期、调整时长、窄窗口及长标题；原生窗口坐标操作当前返回
  noWindowsAvailable，尚未取得拖动或缩放成功的证据。
- 补齐小号／大号小组件、完成后的通知取消和跨午夜刷新；中号组件连续点标题不多开、
  关窗后勾选不弹窗已实测通过。
- 解决或明确记录 CloudKit 的服务器拒绝，取得两台同系统 iCloud 账户 Mac 的同步证据。
- 当前源码、安装产物、MCP 配置和使用文档已经更新。待完成上述设备与同步验收后，
  再更新验收结论；不可把尚未验证的项目标记为完成。

## 构建说明

脚本使用 ~/Library/Developer/Xcode/DerivedData/Daydo-todo，避免 Desktop 的 iCloud
文件元数据影响代码签名。曾通过官方 Git tag 浅克隆缓存解决依赖完整历史下载中断，
脚本使用 -skipPackageUpdates；不关闭 Swift 并发检查，不修改依赖源代码。
安装路径为 ~/Applications/Daydo.app，MCP 配置指向此固定路径。正常 Run 与 --verify
会更新该安装版本；--build 仅生成 dist，--preview 使用独立数据。脚本精确停止被更新的
GUI 和小组件进程，保留既有 MCP 客户端连接；已经建立的连接需要客户端重新连接后
加载新二进制。源码保留在当前项目。
