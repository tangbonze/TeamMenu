# TeamMenu

一个常驻 macOS 菜单栏的 **TeamoRouter 余额 / 用量监控工具**。

A lightweight macOS menu bar app that shows your **TeamoRouter** wallet balance and token usage at a glance.

---

## 功能 / Features

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

## 环境要求 / Requirements

- macOS 13.0 或更高
- Xcode Command Line Tools（提供 `swiftc`）

## 构建 / Build

```bash
git clone <repo-url>
cd TeamMenu
./build.sh
```

产物：`../outputs/TeamMenu.app`（脚本会自动编译、生成图标、ad-hoc 签名）

运行：

```bash
open ../outputs/TeamMenu.app
```

## 开机常驻 / Auto-start

```bash
./install-launchagent.sh
```

会安装 `~/Library/LaunchAgents/com.teammenu.TeamMenu.plist` 并立即启动。

卸载：

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.teammenu.TeamMenu.plist
rm ~/Library/LaunchAgents/com.teammenu.TeamMenu.plist
```

## 配置 / Configuration

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

## 数据来源 / API

TeamoRouter 网关 API：

| 接口 | 用途 |
| --- | --- |
| `GET /v1/billing/balance` | 钱包余额 |
| `GET /v1/usage?start_time=&end_time=` | 指定时间段 Token 用量与请求数 |
| `GET /v1/user/balance` | 账户状态与累计消费 |

## 项目结构 / Layout

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

## 说明 / Notes

- 图标使用 TeamoRouter 官方 logo（App 图标取自官方 `icon.icns`，菜单栏图形取自官方 favicon）。
- 余额按 API 返回的货币展示（默认 USD）；用量统计按「今天（本地时区 0 点至今）」查询。
- 本项目与 TeamoRouter 官方无隶属关系，仅为第三方客户端工具。

## License

[MIT](LICENSE)
