# TeamMenu

[中文](#中文) · [English](#english)

> 常驻 macOS 菜单栏的 **TeamoRouter** 余额 / 用量监控工具
>
> A lightweight macOS menu bar app that shows your **TeamoRouter** wallet balance and token usage at a glance.

---

## 中文

### 功能

- **菜单栏常驻显示余额**（如 `$9.99`）+ 状态点（绿=正常 / 黄=加载中 / 红=出错），默认每 60 秒自动刷新
- **弹出面板**展示：
  - 余额、货币、账户状态、累计消费
  - 今日用量：请求数、总 Tokens、输入 / 输出 / 缓存读写
  - 近 7 日用量柱状图
- **3 套 UI 主题**（面板底部一键切换，选择自动记忆）：
  - **卡片**：蓝色渐变余额卡 + 统计磁贴 + 7 日柱状图
  - **极简**：轻量列表 + 等宽数字 + 全宽趋势条
  - **仪表**：用量进度环 + 彩色统计行
  - 三套主题**固定同一尺寸**，切换不跳动；配色**跟随系统浅色 / 深色自动切换**
- 开机自启动（LaunchAgent，崩溃自动重启）、无 Dock 图标（LSUIElement）
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

TeamoRouter 网关 API：

| 接口 | 用途 |
| --- | --- |
| `GET /v1/billing/balance` | 钱包余额 |
| `GET /v1/usage?start_time=&end_time=` | 指定时间段 Token 用量与请求数 |
| `GET /v1/user/balance` | 账户状态与累计消费 |

### 项目结构

```
TeamMenu.swift              # 应用主源码（配置、API、状态、三套主题 UI）
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
- 余额按 API 返回的货币展示（默认 USD）；用量统计按「今天（本地时区 0 点至今）」查询。
- 本项目为第三方工具，与 TeamoRouter 官方无隶属关系。

### 许可证

[MIT](LICENSE)

---

## English

### Features

- **Balance in the menu bar** (e.g. `$9.99`) with a status dot (green = OK, yellow = loading, red = error), auto-refreshing every 60 seconds
- **Popover panel** showing:
  - Wallet balance, currency, account status and lifetime spend
  - Today's usage: requests, total tokens, input / output / cached read & write
  - Last 7 days usage bar chart
- **3 switchable UI themes** (one click at the bottom of the panel, remembered across launches):
  - **Card** — gradient balance card, stat tiles, 7-day bar chart
  - **Minimal** — compact rows, monospaced numbers, full-width trend bars
  - **Dashboard** — usage progress ring with colored stat rows
  - All themes share the **same fixed panel size** (no jumping) and follow the **system light / dark appearance**
- Auto-start at login via LaunchAgent (restarts on crash), no Dock icon (`LSUIElement`)
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

TeamoRouter gateway endpoints:

| Endpoint | Purpose |
| --- | --- |
| `GET /v1/billing/balance` | Wallet balance |
| `GET /v1/usage?start_time=&end_time=` | Token usage and request count for a time range |
| `GET /v1/user/balance` | Account status and lifetime spend |

### Layout

```
TeamMenu.swift              # App source (config, API, state, three themes)
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
- Balance is displayed in the currency returned by the API (USD by default); usage is queried for "today" (local midnight to now).
- This is an unofficial third-party tool, not affiliated with TeamoRouter.

### License

[MIT](LICENSE)
