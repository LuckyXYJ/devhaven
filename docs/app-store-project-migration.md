# DevHaven macOS App Store / Project 迁移计划

本文档记录当前 `macos/` Swift Package 工程迁移为 Xcode `Project`，并准备 Mac App Store 分发时需要处理的事项。

## 当前现状

- 当前原生端入口是 [`macos/Package.swift`](/Users/xyj/Code/devhaven/macos/Package.swift)。
- App 主 target 是 `DevHavenApp`，依赖：
  - `DevHavenCore`
  - `Vendor/GhosttyKit.xcframework`
  - `Vendor/Sparkle.xcframework`
  - `Sources/DevHavenApp/GhosttyResources`
  - `Sources/DevHavenApp/AgentResources`
- 当前 `.app` 不是由 Xcode app target 产出，而是由 [`macos/scripts/build-native-app.sh`](/Users/xyj/Code/devhaven/macos/scripts/build-native-app.sh) 手工拼装：
  - `swift build`
  - 拷贝可执行文件与资源 bundle
  - 拷贝 `Sparkle.framework`
  - 运行 `codesign --deep`
  - 动态生成 `Info.plist`
- 仓库里目前没有：
  - `.xcodeproj`
  - `.xcworkspace`
  - `Info.plist`
  - `.entitlements`
  - `PrivacyInfo.xcprivacy`

## 结论

要上架 Mac App Store，不能只做“SPM -> Project”格式替换，至少要并行解决两类问题：

1. 工程与构建链路迁到 Xcode app target，支持 Archive / Upload。
2. 商店版能力收敛到 App Sandbox 和 App Review Guidelines 允许的范围内。

当前代码库里，第二类问题比第一类问题更大。

## 主要阻塞项

### 1. Sparkle 不能用于 Mac App Store 版

当前更新链路在 [`macos/Sources/DevHavenApp/Update/DevHavenUpdateController.swift`](/Users/xyj/Code/devhaven/macos/Sources/DevHavenApp/Update/DevHavenUpdateController.swift) 及其相关文件内，并且构建脚本会显式嵌入 `Sparkle.framework`。

Mac App Store 版必须使用 App Store 分发更新，不能保留 Sparkle、自定义 appcast 或下载页更新入口。

这意味着至少要提供一个 `App Store` build flavor，把以下内容从商店版移除或禁用：

- `Sparkle.xcframework`
- `SUFeedURL` / `SUPublicEDKey` 等 Sparkle 配置
- “检查更新”中的 Sparkle / appcast 逻辑
- nightly / stable 外部分发通道文案

### 2. App Sandbox 是硬要求

当前仓库已经有部分用户选择目录接入，见 [`macos/Sources/DevHavenApp/ProjectDirectoryImportSupport.swift`](/Users/xyj/Code/devhaven/macos/Sources/DevHavenApp/ProjectDirectoryImportSupport.swift) 的 security-scoped access。

但 App Store 版仍需要完整补齐：

- app sandbox entitlement
- user-selected file read/write entitlement
- 需要持久访问的目录改成 security-scoped bookmark 持久化
- 所有脱离用户显式授权的文件访问路径逐一审查

### 3. 外部进程执行是最大审核风险

仓库当前大量依赖 `Process()` 启动外部程序，例如：

- [`macos/Sources/DevHavenCore/Storage/NativeGitCommandRunner.swift`](/Users/xyj/Code/devhaven/macos/Sources/DevHavenCore/Storage/NativeGitCommandRunner.swift)
- [`macos/Sources/DevHavenCore/Run/WorkspaceRunManager.swift`](/Users/xyj/Code/devhaven/macos/Sources/DevHavenCore/Run/WorkspaceRunManager.swift)
- `Ghostty` 相关 host / helper 接线

这对 Mac App Store 不是简单的“加 entitlement”问题，而是产品能力边界问题：

- Git CLI 调用是否全部保留
- 用户自定义 Run Script 是否保留
- 内嵌终端是否继续允许执行任意 shell 命令
- CLI helper 是否仍然随 App bundle 分发

从审核风险看，如果商店版继续主打“执行任意 shell / git / agent wrapper / 外部命令”，通过率并不乐观。

### 4. Agent wrapper / shell integration 需要商店版策略

当前资源会向终端注入：

- `AgentResources/bin/claude`
- `AgentResources/bin/codex`
- `devhaven-agent-emit`
- shell integration PATH 修正脚本

这些能力与“下载、执行、包装外部工具”的边界非常接近。即使技术上能在沙盒内运行，审核时也很容易被视为动态改变能力或绕过审查范围。

### 5. 当前构建链路不适合 App Store Connect 上传

现在的本地构建产物依赖 shell 脚本手工拼 bundle，这不适合作为正式的 App Store archive/upload 链路。App Store 版需要切到：

- Xcode target
- Signing & Capabilities
- Archive
- Organizer / `xcodebuild archive`
- App Store Connect 上传

## 建议的迁移顺序

### 阶段 1：先拆出 `App Store` 能力边界

先不要急着生成 `.xcodeproj`，先确定商店版到底保留什么。

建议最低可行商店版只保留：

- 项目管理 UI
- 文件浏览 / diff / 文本查看
- 基础 Git 只读能力，或有限的 repo 操作
- 用户显式选择目录后的访问

建议先从商店版移除或条件编译禁用：

- Sparkle 更新
- Run Script
- 任意 shell 执行
- 终端内执行任意命令
- agent wrapper 与 shell 注入

如果这一步不做，后面即使生成了 `Project`，也大概率只是“能 Archive，但不适合送审”。

### 阶段 2：引入 Xcode Project

目标结构建议：

- `DevHavenApp` macOS app target
- `DevHavenCore` framework target
- `DevHavenCLI` 先改为：
  - 非 App Store flavor 不嵌入，或
  - 拆成单独 target，仅 direct distribution 使用
- `DevHavenAppTests`
- `DevHavenCoreTests`

同时补齐：

- 固定 `Info.plist`
- `Release` / `Debug` / `AppStore` 配置
- `.entitlements`
- 图标、bundle resources、xcframework embed/sign

### 阶段 3：做双发行通道

建议明确分成两条发行线：

- `Direct` 版：保留 Sparkle、终端、agent、CLI helper
- `App Store` 版：沙盒化并裁剪能力

不要试图用一套完全相同的功能同时满足 direct distribution 和 Mac App Store。

## 建议的代码改造点

### A. 增加发行风味开关

建议增加编译条件，例如：

- `DEVHAVEN_APPSTORE`
- `DEVHAVEN_DIRECT`

优先用于裁剪：

- Update 模块
- Run 模块
- Ghostty/CLI helper 接线
- AgentResources 注入

### B. 收口更新入口

需要把 UI 层的“检查更新”改成可替换策略：

- direct 版走 Sparkle / appcast
- App Store 版隐藏入口，或跳转 App Store 产品页

### C. 收口文件访问策略

需要把项目目录、最近项目、恢复快照、日志目录等访问分成：

- 容器内路径
- 用户选择目录
- 临时文件

不能继续默认假设对任意路径都有读写能力。

### D. 收口外部命令执行

建议先抽象一层 capability / backend：

- `NativeGitCommandRunner`
- `WorkspaceRunManager`
- shell / helper 启动点

由 build flavor 决定：

- direct 版：真实执行
- App Store 版：禁用或只读降级

## 建议的实施步骤

### 第一步

先做“商店版裁剪骨架”，具体包括：

- 增加 `App Store` build flag
- 屏蔽 Sparkle 更新
- 屏蔽 Run Script
- 屏蔽 agent / wrapper 注入入口
- 梳理哪些 UI 在商店版下需要隐藏

当前仓库已完成的第一步骨架：

- 已新增发行模型：`DevHavenDistribution / DevHavenDistributionCapabilities`
- 已把 `Workspace Run` 收口到发行能力，并在 App Store flavor 下禁用
- 已把 `Ghostty` 的 agent 环境变量 / CLI helper 注入收口到发行能力
- 已把更新入口收口到发行能力；App Store flavor 下不再走外部分发 updater
- 已补齐 Project 迁移所需静态资产：
  - `macos/project.yml`
  - `macos/Resources/Info-Direct.plist`
  - `macos/Resources/Info-AppStore.plist`
  - `macos/DevHaven-Direct.entitlements`
  - `macos/DevHaven-AppStore.entitlements`
  - `macos/Resources/PrivacyInfo.xcprivacy`
- 已让资源定位器兼容 SwiftPM resource bundle 与 Xcode app main bundle 两种布局

当前仍未完成：

- 终端能力本身的进一步裁剪策略
- Git CLI / 外部命令在商店版中的最终保留边界
- 签名后的 Export / Upload 链路
- entitlements / sandbox 持久化访问方案

### 第二步

在裁剪骨架稳定后，再创建 Xcode Project，并完成：

- app target
- test targets
- resources / xcframework embed
- `Info.plist`
- `.entitlements`
- Archive 验证

当前建议直接用 `macos/project.yml` 生成工程：

```bash
cd macos
xcodegen generate
```

说明：

- `project.yml` 当前描述了两条配置：
  - `DevHaven Direct`
  - `DevHaven App Store`
- App Store 配置会启用 `DEVHAVEN_APPSTORE`

截至 2026-04-12，当前环境已完成：

- 已通过 `brew install xcodegen` 安装 `xcodegen`
- 已生成工程：`macos/DevHavenNative.xcodeproj`
- 已通过工程级编译验证：
  - `xcodebuild -project DevHavenNative.xcodeproj -scheme 'DevHaven Direct' -configuration Debug CODE_SIGNING_ALLOWED=NO build`
  - `xcodebuild -project DevHavenNative.xcodeproj -scheme 'DevHaven App Store' -configuration AppStoreDebug CODE_SIGNING_ALLOWED=NO build`
- 已通过 App Store 归档验证：
  - `xcodebuild -project DevHavenNative.xcodeproj -scheme 'DevHaven App Store' -configuration AppStoreRelease CODE_SIGNING_ALLOWED=NO archive -archivePath /tmp/DevHavenAppStore-final.xcarchive`
  - 归档结果：
    - `CFBundleShortVersionString = 3.1.10`
    - `CFBundleVersion = 3011000`
    - `LSApplicationCategoryType = public.app-category.developer-tools`
    - `Architectures = arm64 + x86_64`
  - 当前 archive 中不再把 `libghostty.a` 误嵌入到 `DevHaven.app/Contents/Frameworks`

当前 `project.yml` 的实现策略：

- Direct 版：
  - 独立 app target
  - 依赖 `DevHavenCLI`
  - 链接 `Sparkle.xcframework`
- App Store 版：
  - 独立 app target
  - 不依赖 `DevHavenCLI`
  - 不链接 `Sparkle.xcframework`
- 运行时资源：
  - 不再通过单独 resources bundle target 编译
  - 改为 app target build script 直接复制 `GhosttyResources` / `AgentResources`
  - 避开 `.d` 文件被 Xcode 误判为 DTrace script 的问题

### 第三步

最后处理上传与审核准备：

- App Store Connect app record
- bundle id / signing / provisioning
- 沙盒测试
- TestFlight
- 审核说明

## 参考

- Apple Developer: App Sandbox
  - https://developer.apple.com/documentation/security/app-sandbox
- Apple Developer: Accessing files from the macOS App Sandbox
  - https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox
- Apple Developer: Distributing your app for beta testing and releases
  - https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases/
- Apple Developer: Upload builds
  - https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/

补充说明：

- 关于 Mac App Store 的额外限制与 2.5.2 / 2.4.5 系列要求，本文基于 Apple 官方指南当前文字和本仓库现状做工程判断。
- 其中“Sparkle 不应出现在 Mac App Store 版”和“任意 shell / 外部进程执行存在明显审核风险”属于基于 Apple 规则对当前功能模型的工程推断。
- 截至 2026-04-12，本次骨架改动后的本地 `swift build --package-path macos` 校验已恢复通过；新增加的 `plist / entitlements / privacy manifest` 也已通过 `plutil -lint` 校验。
- 截至 2026-04-12，生成后的 `.xcodeproj` 已能完成 no-sign Debug build 和 no-sign App Store archive；说明“Swift Package -> Xcode Project -> Archive”这条工程链路已经打通。
- 当前剩余的 Xcode 级噪音主要有两条：
  - `appintentsmetadataprocessor` 提示未发现 `AppIntents.framework`，这是无功能依赖时的工具警告。
  - `dsymutil` 会对 `libghostty.a(ext.o)` 打出缺失 `ImFontConfig_ImFontConfig / ImGuiStyle_ImGuiStyle` 的符号警告；目前不影响 archive 成功，但在正式送审前最好确认 Ghostty vendor 是否需要更新或重新产出调试符号。
