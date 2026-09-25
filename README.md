# TeamMenu

[中文](#中文) · [English](#english)

> 常驻 macOS 菜单栏的 **TeamoRouter** 余额 / 用量 / 消费监控工具
>
> A lightweight macOS menu bar app that shows your **TeamoRouter** balance, token usage and spending.

---

## 中文

### 功能

**菜单栏**
- 常驻显示**余额**（如 `$9.99`）+ 状态点（绿=正常 / 黄=加载中 / 红=出错）
- 默认每 60 秒自动刷新，无 Dock 图标

**弹出面板（四个标签页）**

| 标签 | 内容 |
| --- | --- |
| **概览** | 余额、可用 / 冻结金额、今日花费、累计消费；今日请求数与 Token 明细（输入 / 输出 / 缓存读写）；近 7 日花费图表 |
| **明细** | 每笔消费记录：模型、时间、金额、Token 数；充值记录以绿色 `+$xx` 单独标识 |
| **模型** | 今日按模型的请求数、Token 用量、花费及占比条（按花费排序） |
| **健康** | 各模型服务 SLA / 成功率（成功/总请求），按请求量排序，颜色分级 |

**三套 UI 主题**（面板底部一键切换，选择自动记忆）
- **卡片**：渐变余额卡 + 花费/可用/冻结卡片 + 统计磁贴 + 7 日花费柱状图
- **极简**：轻量列表 + 等宽数字 + 全宽趋势条
- **仪表**：今日花费进度环 + 彩色统计行

三套主题**固定同一尺寸**（360 × 540），切换不跳动；配色**跟随系统浅色 / 深色自动切换**。

**其他**
- 开机自启动（LaunchAgent，崩溃自动重启）
- 无第三方依赖，纯 SwiftUI + AppKit

### 环境要求

- macOS 13.0 或更高
- Xcode Command Line Tools（提供 `swiftc`）

### 构建

```bash
git clone https://github.com/tangbonze/TeamMenu.git
cd TeamMenu
./build.sh
```

产物：`../outputs/TeamMenu.app`（脚本会自动编译、生成图标、ad-hoc 签名）

默认构建当前机器架构；如需 **通用二进制**（Apple Silicon + Intel）：

```bash
UNIVERSAL=1 ./build.sh
```

运行：

```bash
open ../outputs/TeamMenu.app
```

### 开机常驻

```bash
./install-launchagent.sh
```

会安装 `~/Library/LaunchAgents/com.teammenu.TeamMenu.plist` 并立即启动。

卸载：

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.teammenu.TeamMenu.plist
rm ~/Library/LaunchAgents/com.teammenu.TeamMenu.plist
```

### 配置

默认自动读取 Teamo 桌面端的登录信息，**无需手动配置**：

```
~/Library/Application Support/com.teamolab.teamorouter/login-session.json
```

如需自定义，创建 `~/Library/Application Support/TeamMenu/config.json`（参考 `config.example.json`）：

```json
{
  "api_key": "sk-teamo-...",
  "base_url": "https://api.teamorouter.cn/v1",
  "refresh_interval": 60,
  "username": "your-account"
}
```

优先级：`config.json` > Teamo 登录会话 > 环境变量（`TEAMO_API_KEY`、`TEAMO_BASE_URL`、`TEAMO_REFRESH_INTERVAL`）。

### 数据来源

| 接口 | 用途 |
| --- | --- |
| `GET /v1/billing/me/balance` | 余额、可用 / 冻结金额、累计消费、账户状态 |
| `GET /v1/billing/me/transactions` | 交易明细（每笔的模型、金额、Token、类型） |
| `GET /v1/billing/sla/overview` | 各模型 SLA 与成功率 |
| `GET /v1/usage?start_time=&end_time=` | 指定时间段的 Token 用量与请求数 |

### 实现说明

- **花费口径**：只统计 `type = COMMIT` 的记录；`RECHARGE`（充值）金额为负数，单独展示，不计入花费。
- **交易分页**：接口忽略 `page_size`，固定每页 20 条。应用在启动时全量回填（上限 40 页），之后每次刷新只拉最新 2 页并与本地缓存合并去重，避免高频请求。
- **数据范围**：7 日图表仅统计可回溯到的记录；超出回溯范围的日期以灰条占位，不显示为 0。
- **SLA 刷新**：每 5 分钟拉取一次（数据量较大）。

### 项目结构

```
TeamMenu.swift              # 应用主源码（配置、API、状态、四标签页、三套主题）
build.sh                    # 构建脚本
install-launchagent.sh      # 开机自启安装脚本
assets/                     # 官方 logo 资源（favicon + 菜单栏 PNG）
make-menubar-logo.py        # 从官方 favicon 生成菜单栏 logo
make-icns.py                # 打包 .icns（iconutil 不可用时的替代）
extract-icns-png.py         # 从 .icns 提取 PNG
make-icon.swift             # 生成备用图标
config.example.json         # 配置示例
```

### 说明

- 图标使用 TeamoRouter 官方 logo（App 图标取自官方 `icon.icns`，菜单栏图形取自官方 favicon）。
- 本项目为第三方工具，与 TeamoRouter 官方无隶属关系。

### 许可证

[MIT](LICENSE)

---

## English

### Features

**Menu bar**
- Live **balance** (e.g. `$9.99`) with a status dot (green = OK, yellow = loading, red = error)
- Auto-refresh every 60 seconds, no Dock icon

**Popover panel (four tabs)**

| Tab | Contents |
| --- | --- |
| **Overview** | Balance, available / frozen amount, today's spend, lifetime spend; today's requests and token breakdown (input / output / cached read & write); 7-day spend chart |
| **Transactions** | Every charge: model, time, amount, tokens. Recharges are shown separately in green (`+$xx`) |
| **Models** | Today's per-model requests, tokens, cost and share bar (sorted by cost) |
| **Health** | Per-model SLA / success rate (success / total requests), sorted by volume, color-coded |

**Three UI themes** (one click at the bottom of the panel, remembered across launches)
- **Card** — gradient balance card, spend/available/frozen chips, stat tiles, 7-day spend bars
- **Minimal** — compact rows, monospaced numbers, full-width trend bars
- **Dashboard** — today's spend progress ring with colored stat rows

All themes share the **same fixed size** (360 × 540) and follow the **system light / dark appearance**.

**Other**
- Auto-start at login via LaunchAgent (restarts on crash)
- No third-party dependencies — pure SwiftUI + AppKit

### Requirements

- macOS 13.0 or later
- Xcode Command Line Tools (provides `swiftc`)

### Build

```bash
git clone https://github.com/tangbonze/TeamMenu.git
cd TeamMenu
./build.sh
```

Output: `../outputs/TeamMenu.app` (the script compiles, generates the icon and ad-hoc signs the bundle)

By default it builds for the current architecture. For a **universal binary** (Apple Silicon + Intel):

```bash
UNIVERSAL=1 ./build.sh
```

Run:

```bash
open ../outputs/TeamMenu.app
```

### Auto-start

```bash
./install-launchagent.sh
```

Installs `~/Library/LaunchAgents/com.teammenu.TeamMenu.plist` and starts it immediately.

Uninstall:

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.teammenu.TeamMenu.plist
rm ~/Library/LaunchAgents/com.teammenu.TeamMenu.plist
```

### Configuration

By default the app reads the credentials of the Teamo desktop app — **no manual setup needed**:

```
~/Library/Application Support/com.teamolab.teamorouter/login-session.json
```

To customize, create `~/Library/Application Support/TeamMenu/config.json` (see `config.example.json`):

```json
{
  "api_key": "sk-teamo-...",
  "base_url": "https://api.teamorouter.cn/v1",
  "refresh_interval": 60,
  "username": "your-account"
}
```

Priority: `config.json` > Teamo login session > environment variables (`TEAMO_API_KEY`, `TEAMO_BASE_URL`, `TEAMO_REFRESH_INTERVAL`).

### API

| Endpoint | Purpose |
| --- | --- |
| `GET /v1/billing/me/balance` | Balance, available / frozen amount, lifetime spend, account status |
| `GET /v1/billing/me/transactions` | Transaction records (model, amount, tokens, type) |
| `GET /v1/billing/sla/overview` | Per-model SLA and success rate |
| `GET /v1/usage?start_time=&end_time=` | Token usage and request count for a time range |

### Implementation notes

- **Spend accounting** counts only `type = COMMIT` records. `RECHARGE` amounts are negative and are displayed separately, never counted as spend.
- **Transaction pagination**: the API ignores `page_size` and always returns 20 rows per page. The app performs a full backfill on launch (capped at 40 pages) and then fetches only the newest 2 pages per refresh, merging into a local cache by `tx_id`.
- **Data coverage**: the 7-day chart only covers records the app could reach; days outside that range are drawn as a dim placeholder instead of `$0`.
- **SLA** is fetched at most once every 5 minutes (the payload is large).

### Layout

```
TeamMenu.swift              # App source (config, API, state, four tabs, three themes)
build.sh                    # Build script
install-launchagent.sh      # Auto-start installer
assets/                     # Official logo assets (favicon + menu bar PNG)
make-menubar-logo.py        # Generate the menu bar logo from the official favicon
make-icns.py                # .icns packer (fallback when iconutil is unavailable)
extract-icns-png.py         # Extract a PNG from an .icns
make-icon.swift             # Fallback icon generator
config.example.json         # Example configuration
```

### Notes

- Icons use the official TeamoRouter logo (the app icon comes from the official `icon.icns`, the menu bar glyph from the official favicon).
- This is an unofficial third-party tool, not affiliated with TeamoRouter.

### License

[MIT](LICENSE)
