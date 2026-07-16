# File Inbox Assistant

[![macOS](https://img.shields.io/badge/macOS-13%2B-black)](https://www.apple.com/macos/)
[![SwiftBar](https://img.shields.io/badge/SwiftBar-plugin-0a84ff)](https://github.com/swiftbar/SwiftBar)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-required-d97757)](https://docs.anthropic.com/en/docs/claude-code/overview)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![test](https://github.com/shaowen-ye/file-inbox-assistant/actions/workflows/test.yml/badge.svg)](https://github.com/shaowen-ye/file-inbox-assistant/actions/workflows/test.yml)

中文 | [English summary](#english-summary)

**文件收件箱助手**是一个面向 macOS 的本地文件整理工作流：把待整理文件放入统一收件箱，由 Claude Code 根据你自己的规则提出归档位置和规范名称，再通过受限脚本安全移动、记账，并支持撤销。

菜单栏入口由 [SwiftBar](https://github.com/swiftbar/SwiftBar) 提供。本仓库不分发或修改 SwiftBar 应用本体。

## 功能

- 监测收件箱顶层的新文件、文件夹和 macOS bundle。
- 等待复制完成后再触发处理，避免移动尚未写完的文件。
- 分类规则完全由本地 `rules.md` 决定，不绑定任何个人目录体系。
- 高置信度自动归档，低置信度进入 `_Needs Review`。
- 所有移动只经过一个受限脚本：不覆盖、同内容判重、移动后校验。
- JSONL 迁移账本、最近批次预演和一键撤销。
- SwiftBar 菜单显示收件箱数量、会话状态及常用操作。
- 不包含遥测、个人路径、真实账本、API 密钥或私人分类规则。

## 运行结构

```text
File Inbox
   │
   ├─ watcher (tmux)
   │      └─ 发现稳定文件后触发 Claude Code
   │
   ├─ Claude Code + rules.md
   │      └─ 读取、分类、命名、给出置信度
   │
   └─ archive-move.sh
          ├─ File Archive
          ├─ _Needs Review
          └─ ledger.jsonl + undo
```

## 安装要求

- macOS 13 或更高版本。
- [SwiftBar](https://github.com/swiftbar/SwiftBar)。
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/getting-started)。
- `tmux` 和 `jq`。
- 可选：`poppler`（读取 PDF）、`pandoc`（读取 Office/Markdown 文档）。

使用 Homebrew 安装常用依赖：

```bash
brew install swiftbar tmux jq poppler pandoc
npm install -g @anthropic-ai/claude-code
```

## 快速开始

```bash
git clone https://github.com/shaowen-ye/file-inbox-assistant.git
cd file-inbox-assistant
./install.sh
```

安装器默认创建：

```text
~/Documents/File Inbox
~/Documents/File Archive
~/Documents/File Inbox Backlog
~/.config/file-inbox-assistant/config.sh
~/.config/file-inbox-assistant/rules.md
~/.local/share/file-inbox-assistant/
~/.local/state/file-inbox-assistant/ledger.jsonl
```

接着完成三步：

1. 编辑 `~/.config/file-inbox-assistant/rules.md`，把示例分类替换成你的真实归档规则。
2. 在“系统设置 > 隐私与安全性 > 完全磁盘访问”中允许你使用的终端和 SwiftBar 访问文件。
3. 运行 `file-inbox`，或点击 SwiftBar 菜单中的“启动 / 进入整理会话”。

安装器会提示把下面的 alias 加入 shell 配置：

```bash
alias file-inbox='bash "$HOME/.local/share/file-inbox-assistant/scripts/start-session.sh"'
```

## 配置

路径、模型、轮询间隔和终端应用均在：

```text
~/.config/file-inbox-assistant/config.sh
```

常用设置：

```bash
INBOX="$HOME/Documents/File Inbox"
ARCH_ROOT="$HOME/Documents/File Archive"
MODEL="sonnet"
TERMINAL_APP="Terminal" # 或 iTerm
CONFIDENCE_THRESHOLD="0.80"
```

修改配置后，退出并重新启动 `file-inbox` tmux 会话。

## 隐私边界

这是本地编排工具，但**不等于所有处理都只发生在本机**：Claude Code 为判断文件内容，可能把读取到的文本发送给你配置的 Claude 服务。请在使用前理解并接受相应服务的数据政策。

- 默认敏感文件名模式（例如 `.env`、私钥、密码、token）会被标记为敏感。
- 敏感条目不得读取正文，只能移入 `_Needs Review`。
- 建议把包含高度敏感信息的目录完全排除在收件箱之外。
- 本项目不收集遥测，不上传账本，也不内置任何密钥。

## 安全设计

- 源路径必须位于收件箱内。
- 目标路径必须位于归档根目录内，并拒绝 `..` 和符号链接跳转。
- 绝不覆盖现有文件；冲突自动追加编号。
- 同名同内容文件移入 `_Needs Review/_Duplicates`。
- 默认撤销为预演；只有 `--apply` 才移动文件。
- 文件移动和账本操作有互斥锁，避免并发执行。

仍建议先在测试目录运行，并保持 Time Machine 或其他备份。

## 手动命令

```bash
# 查看待处理清单
~/.local/share/file-inbox-assistant/scripts/scan.sh

# 查看最近迁移记录
~/.local/share/file-inbox-assistant/scripts/review-ledger.sh --recent 30

# 预演撤销最近批次
~/.local/share/file-inbox-assistant/scripts/undo-last.sh

# 确认撤销
~/.local/share/file-inbox-assistant/scripts/undo-last.sh --apply
```

## 项目边界

- 这是 Claude Code + SwiftBar 的工作流，不是独立的原生 macOS 文件管理器。
- 分类质量取决于 `rules.md`、可读取的文件内容和模型判断。
- 不应把它作为唯一备份或无人工监督的高风险文件迁移系统。
- 本项目与 Anthropic、SwiftBar 或 Apple 没有关联，也未获得其背书。

## English summary

File Inbox Assistant is a macOS workflow that watches a local inbox, asks Claude Code to classify stable files according to user-owned rules, and moves them through a constrained, auditable shell layer. It includes a SwiftBar menu, duplicate protection, a JSONL ledger, and dry-run-first undo. No SwiftBar binary, personal paths, private filing rules, logs, or credentials are included.

Before using it, review the [privacy boundary](#隐私边界), customize `rules.md`, and test with disposable files.

## License

MIT. See [LICENSE](LICENSE). SwiftBar and Claude Code are separate third-party projects governed by their own licenses and terms.
