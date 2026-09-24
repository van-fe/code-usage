# CodeUsage

[English](README.md) | 简体中文

<p align="center">
  <img src="Assets/AppIcon-1024.png" width="112" alt="CodeUsage 应用图标">
</p>

CodeUsage 是一款轻量、原生的 macOS 菜单栏应用，用一个面板集中查看 Codex、Cursor、Claude Code、Kiro 和 Qoder 的用量与额度。

项目主页：<https://github.com/van-fe/code-usage>

> CodeUsage 是非官方第三方工具，与 OpenAI、Cursor、Anthropic、AWS、Kiro 或 Qoder 没有隶属或背书关系。各名称与标识归其权利人所有。

## 功能

- 状态栏支持“简略 / 中度 / 完整”三档展示，并可按工具独立显示或隐藏。
- 提供一个随小、中、大尺寸自动调整内容的系统小组件；macOS 13+ 可放入通知中心，macOS 14+ 也可直接放到桌面。
- 点击状态栏打开右对齐面板，面板打开期间保持原生选中状态。
- 一键刷新用量、一键打开对应应用；操作按钮提供悬浮反馈。
- 每 5 分钟自动刷新；请求失败时保留上次成功数据并标记为旧数据。
- 区分 Cursor 的基础套餐额度、个人消费与团队或组织汇总；Enterprise 共享池按服务端口径显示。
- 提供隔离的订阅模拟模式，可依次检查免费、个人、团队与企业订阅的界面分组。
- 支持登录 Mac 后自动启动，可随时在面板底部关闭。
- 可主动开启 iCloud，同步经过裁剪的用量展示快照，供后续 iPhone 客户端读取。
- 底部 GitHub 按钮可直接打开 CodeUsage 项目主页。
- 未检测到受支持工具时显示清晰的空白状态和操作提示。
- 无遥测，不把登录令牌写入 CodeUsage 的日志或用量快照。

## 支持的工具

| 工具 | 显示内容 | 本机要求 |
| --- | --- | --- |
| Codex | 服务端返回的 5 小时、7 天、月度等套餐窗口，以及可用的额外 Credits | 安装并登录 Codex CLI、Codex App，或包含 Codex 的 ChatGPT App |
| Cursor | 个人套餐额度或服务端进度、个人消费；支持时另列团队或组织汇总 | 安装并登录 Cursor |
| Claude Code | 当前 Claude 账号共用的 5 小时与 7 天订阅额度 | 安装并登录 Claude Code CLI |
| Kiro | 月度套餐 Credits，以及登录方式支持且接口返回的已购 Add-on | 安装并登录 Kiro IDE 或 Kiro CLI |
| Qoder | 套餐 Credits、接口返回的 Add-on 与组织共享 Credits | 安装并登录 Qoder IDE 或 Qoder CLI；仅安装 IDE 时需保持 IDE 运行 |

只会显示本机已检测到的工具。安装或登录状态发生变化后，可点击面板右上角的刷新按钮重新检测。

### 团队与企业账号

下表说明普通成员登录态下可显示的数据；具体项目仍以服务端实际返回为准。团队或企业订阅名称本身不代表应用能读取管理员账单。

| 工具 | 当前成员可见 | 团队或组织数据 | 不推算的数据 |
| --- | --- | --- | --- |
| Codex Business / Enterprise | 5 小时、7 天等套餐窗口；服务端返回时显示个人上限 | 服务端返回时显示工作区 Credits 余额 | 团队总消费、团队预算百分比 |
| Cursor Team / Enterprise | 个人基础套餐额度或服务端综合进度、个人消费 | 服务端返回时显示团队或组织汇总及上限；Enterprise 共享池可能覆盖合同期总用量 | 不用团队总额代替个人消费 |
| Claude Code Team / Enterprise | 当前成员的 5 小时与 7 天额度 | 普通 OAuth 登录态下不显示组织消费 | 组织按量消费、团队总预算 |
| Kiro Enterprise | 当前成员的月度套餐 Credits | 当前个人接口未提供可靠的组织消费 | 企业超额消费及管理员侧配额 |
| Qoder 团队 / 企业 | 套餐 Credits；接口返回 `addOnQuota` 时显示 Add-on | 接口返回时显示组织共享 Credits | 不把共享 Credits 换算成美元或推断管理员账单 |

## 用量口径

### Cursor

Cursor 的指标分为套餐额度与消费或共享额度：

- **套餐额度**：旧计费方式保留 Cursor 返回的综合、Auto 和其他模型（API）进度百分比。这些不是可相加的消费金额，`autoPercentUsed` 也不等于选择 Auto 的请求用量。新 Team 计费方式显示个人基础套餐额度与第三方模型（API）进度；基础额度达到 100% 不表示赠送用量已用完或已开始按量付费。
- **消费与共享额度**：个人方案显示“本期消费”，团队方案分别显示“我的消费”和团队汇总。个人金额优先取 Cursor 的个人消费字段；新 Team 方式缺少该字段时，才使用个人用量汇总中的按量付费金额。两者都没有时，不用团队总额代替个人金额。Enterprise 共享池可能包含合同期的总用量，不能一律当作超额付费。

如果 Cursor 没有返回个人消费上限，可以在 CodeUsage 中设置“显示预算”。它只用于计算本地进度，不会修改 Cursor 后台的上限或阻止实际消费。个人消费有可计算进度时，状态栏优先显示其剩余比例，无论进度来自服务端上限还是显示预算；否则显示套餐主指标。旧计费方式的综合进度剩余比例不等于金额余额。

### Codex

CodeUsage 按服务端实际返回的窗口显示 5 小时、7 天、月度等套餐内限额。Business 或 Enterprise 计划若返回个人上限或工作区 Credits，会另列在“额外 Credits”中。工作区 Credits 是可能由多位成员及受支持功能共用的余额，不是个人余额或团队总预算；应用不会根据缺失字段反推团队百分比。

### Claude Code

显示当前 Claude 账号的订阅额度，Claude 与 Claude Code 共用这些额度。Claude Team 通常按 seat 独立计量，并非团队共享池；普通 Claude Code OAuth 登录态不提供组织消费，因此 CodeUsage 不会推算金额或团队预算。

### Kiro

显示当前账号的月度套餐 Credits。仅在社交登录或 AWS Builder ID 登录方式支持、且接口返回尚未过期的已购额度时显示 Add-on；这不是对账号购买类型的独立核验。Enterprise overage 需要管理员侧报表或 AWS 配额数据，不能从个人接口可靠推算。

### Qoder

安装了 Qoder CLI 时，CodeUsage 会优先通过 CLI 读取套餐 Credits、接口返回的 Add-on 与组织共享 Credits，不要求 Qoder IDE 保持运行；CLI 不可用时再尝试 Qoder IDE 本机服务。收到 `addOnQuota` 就显示 Add-on，不另行核验账号是否属于个人购买型。额外额度以 Credits 计量，不换算成美元，也不会从普通用户登录态推断管理员 OpenAPI 数据。

Qoder 用量接口的 `expiresAt` 表示当前套餐 Credits 的到期/清零边界，因此界面显示“到期”，不会把它无条件描述为下一次重置；续费后的新周期额度由 Qoder 服务端另行发放。

## 订阅模拟模式

模拟模式不会读取或覆盖真实账号数据，用于按订阅类型检查界面：

```bash
open -a CodeUsage --args --subscription-simulation
```

打开后可在面板顶部依次切换“免费试用”“个人用户”“团队用户”“企业用户”。退出并正常启动 CodeUsage 后，会自动恢复真实数据模式。

## 安装

### 使用 DMG（推荐）

1. 前往 [Releases](https://github.com/van-fe/code-usage/releases) 下载最新的 `CodeUsage-*-macos-universal.dmg`。
2. 打开 DMG，将 `CodeUsage.app` 拖入“应用程序”文件夹。
3. 启动 CodeUsage，状态栏会出现仪表盘图标和已启用工具主指标的剩余比例。

可从齿轮菜单选择状态栏模式。添加系统小组件时，在 macOS 小组件图库中选择 CodeUsage，再按需要选择尺寸。在 macOS 14 或更新版本中，右键点击小组件并选择“编辑小组件”：小号可选 1 个指标，中号最多可选 3 个指标，大号始终按工具分组显示全部指标。

Universal 构建同时支持：

- Apple Silicon：`arm64`
- Intel：`x86_64`

应用系统要求：macOS 13 Ventura 或更新版本；可编辑的系统小组件要求 macOS 14 Sonoma 或更新版本。

### 签名与安全

官方发布包已使用 Apple Developer ID 签名并完成 Apple 公证，可直接正常启动。建议仅从本项目的 [Releases](https://github.com/van-fe/code-usage/releases) 页面下载安装包。

## 数据来源与隐私

CodeUsage 只在本机读取现有登录状态，并向各工具自己的用量接口发起请求：

- **Codex**：启动本机 `codex app-server`，调用 `account/rateLimits/read`；不读取 `~/.codex/auth.json`。
- **Cursor**：只读 Cursor 本机状态数据库取得现有登录态。刷新令牌只用于内存中的会话续期，不写回磁盘。
- **Claude Code**：读取 Claude Code 已保存的 OAuth 登录态。刷新令牌只用于内存中的会话续期，不写回磁盘。
- **Kiro**：读取 Kiro IDE 或 CLI 的本机登录记录。受支持的社交登录过期时，会使用已有 refresh token 续期，并把新凭证保存回 Kiro 原有的凭证文件或 CLI 数据库；不读取设备注册密钥或浏览器 Cookie。
- **Qoder**：优先调用已登录的 Qoder CLI 的本机用量控制接口；CLI 不可用时，才通过所有者和权限校验后的 `.info.json` 与 Unix Socket 调用 Qoder IDE 的 JSON-RPC。认证由 Qoder 处理，CodeUsage 不读取、解密或保存 Qoder token。

应用不包含遥测，不会上传用量数据到 CodeUsage 自己的服务器。系统小组件只读取本机 App Group 快照，其中仅包含工具名称、套餐名称、用量指标、百分比、金额/数量、旧数据状态与刷新时间。iCloud 同步默认关闭；用户主动开启后，只把工具名称、套餐名称、用量指标、百分比、金额/数量和刷新时间写入用户自己的 CloudKit 私有数据库。访问令牌、刷新令牌、Cookie、本机数据库、文件路径、原始命令输出和服务端原始响应均不会进入这两种快照。Cursor 与 Kiro 的部分客户端协议不是公开稳定 API；字段变化时，应用会尽量保留其它可用指标并显示明确错误。

## 从源码构建

需要：

- macOS 13 或更新版本
- Swift 6 工具链
- Xcode Command Line Tools

运行测试并构建当前架构版本：

```bash
./Scripts/test.sh
./Scripts/package.sh
open dist/CodeUsage.app
```

构建同时支持 Apple Silicon 与 Intel 的 Universal 应用和 ZIP：

```bash
./Scripts/package_universal.sh
```

将 `dist/CodeUsage.app` 打包为带语言中立拖拽安装界面的 DMG，并直接写入 `dist/`：

```bash
./Scripts/package_dmg.sh
```

首次生成 DMG 时，macOS 可能请求允许终端控制 Finder，以写入图标位置和窗口背景。

生成源码压缩包：

```bash
./Scripts/package_source.sh
```

DMG 默认写入项目内的 `dist/`；Universal ZIP 和源码压缩包默认写入 `outputs/`。如需写入其它目录，可设置 `CODEUSAGE_OUTPUT_DIR`。

`package.sh`、`package_universal.sh` 等常规本地打包脚本默认使用 ad-hoc 签名；官方发布包通过本机发布流程使用 Developer ID Application、Hardened Runtime 和安全时间戳签名，并完成 Apple 公证。

GitHub Actions、Release Please 自动版本维护，以及“Apple 凭证只保留在本机 Keychain”的正式签名发布流程见 [RELEASING.md](RELEASING.md)。

## 项目结构

```text
CodeUsage/
├── Sources/CodeUsage/   # SwiftUI 界面、状态栏控制与各工具用量 Provider
├── Assets/              # 应用图标、工具图标和 DMG 背景
├── Scripts/             # 测试、单架构、Universal、DMG 与源码打包脚本
├── dist/                # 当前架构的 App 与 DMG（不提交到 Git）
├── outputs/             # 本地生成的发布包（不提交到 Git）
├── LICENSE              # CodeUsage 专有源码可见许可证
├── Package.swift
├── README.md
├── README.zh-CN.md
└── THIRD_PARTY_NOTICES.md
```

## 常见问题

### 安装了工具但没有显示

确认对应工具已经登录，然后点击面板右上角刷新。检测到 CLI 未登录或登录过期时，卡片会显示对应登录命令并提供复制按钮；登录完成后刷新即可。Qoder 如果只安装了 IDE，需要保持 Qoder IDE 正在运行。

### 为什么 Cursor 的综合、Auto 和 API 进度不能相加？

旧计费方式下，这些百分比是不同口径的进度，不是可相加的消费金额。新 Team 计费方式改为显示个人基础套餐额度和第三方模型进度，不把 Auto 百分比当作 Auto 请求用量。

### 为什么没有显示团队总预算？

CodeUsage 只展示当前登录态能够可靠读取的数据。若服务端没有返回团队预算或组织消费权限，应用不会通过个人数据猜测团队额度。

## 第三方说明

工具名称和单色标识仅用于识别对应服务。完整来源、许可和商标说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 许可证

CodeUsage 采用[专有源码可见许可证](LICENSE)，不是开源软件。

允许用户免费下载、安装和使用由作者发布的官方未修改版本。未经作者书面授权，不得修改、二次开发、重新打包、再分发、销售或商业化，也不得将官方或修改后的版本上架任何应用商店、软件市场、包仓库或下载平台。第三方材料仍分别适用 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 中列明的许可条款。
