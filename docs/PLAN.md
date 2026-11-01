# Understage — 开源 Finder 文件 Agent

吸附在 Finder 窗口下方的自然语言命令栏。选中文件，用中文或英文说要做什么，Understage 调用本机工具完成：转码、整理、重命名、压缩、OCR、PDF、git。开源、BYOK、本地模型一等公民。

仓库即本目录。

## 已锁定的决定

- **智能层：三层混合。** Instant（解析器，不走模型）→ Command（一次 LLM 生成可预演 shell）→ Agent（inspect / run / read 工具循环）。危险操作永远确认。
- **第一刀：M0 Spike。** 只验证 Finder 吸附与选中项，不接 AI、不接 ffmpeg。平台层不过就停。
- **许可证：MIT。**
- **栈：原生 Swift 6 + SwiftUI/AppKit + XcodeGen。** macOS 15+，非沙盒，en + zh-Hans。
- **密钥：Keychain。** 不捆绑任何云端 token 订阅。

---

## 1. Substage 在做什么（对照基准）

Substage（Selkie Design，macOS 15+）不是聊天机器人，是 **自然语言 → Terminal 命令** 的薄层：

1. 用 Accessibility + Automation 吸附到每个 Finder 窗口底部，读取当前目录和选中项。
2. 常见短词（`jpg` / `zip` / `1080p mp4`）走 **Instant Actions**，不调模型。
3. 其余请求交给 LLM 生成 bash，再用自制 bash 解释器 **Predicts** 预演：将创建/改名/覆盖/删除/出网哪些文件。
4. 按风险策略自动跑或先确认。禁止 `sudo`。
5. 真正干活的是本机工具：`sips`、`ffmpeg`、`zip`、`qpdf`、`pandoc`、`git`、Tesseract。AI 在命令生成后退出。
6. 1.0 起有 Rules、Ideas & Actions、Favorites、并行长任务、Desktop 浮动栏、Smart Folder、follow-up。
7. 模型：内置订阅，或 BYOK（OpenAI / Anthropic / Google / Mistral）+ Ollama / LM Studio / 任意 OpenAI-compatible。
8. 明确不做：ForkLift / Path Finder；不做内容理解（不能“把猫的照片放进一个文件夹”除非走视觉模型）。

Understage 对标这些交互，并在三点上拉开差距：**开源、真 Agent 循环、本地/多 vendor 一等公民。**

---

## 2. 产品定位

一句话：把 **文件操作 Agent** 做成 Finder 的输入框。

- 不是 Cursor。默认不做大型代码库重构。
- 不只是 Substage 克隆。复杂任务可以多步：看文件 → 计划 → 执行 → 看结果 → 再执行。
- 快路径不经过 AI。`jpg`、`zip`、`mp3` 必须瞬时。

三层执行（已锁定）：

| 层 | 何时 | 延迟 | 例子 |
|---|---|---|---|
| Instant | 短词/短语命中解析器 | <50ms | `jpg`、`zip`、`1080p`、`词数`、`选中所有 pdf` |
| Command | 单步、可预演的 shell | 一次 LLM | `转成 1080p 30fps 1000k mp4`、`把这些 png 按日期归档` |
| Agent | 多步、要读内容、要试错 | 工具循环 | `把 Downloads 里乱七八糟的按类型整理，视频压成 1080p，重复文件进 _dupes` |

用户在设置里可把默认层设成「尽量 Instant / Command」或「允许 Agent」。危险操作永远确认。Agent 层在 M3 才做，M0/M1 只把前两层的接口留好。

---

## 3. 相对 Substage 的差异化（建议一并做进设计，按里程碑落地）

1. **开源、无订阅模型捆绑。** 用户自带 key 或本地模型。不卖 token。
2. **Agent 循环。** 工具：`inspect`（ffprobe/mdls/file/exif）、`run`、`read_text`、`list`、`trash`、`reveal`、`ask_user`。失败可重试，而不是一次性 dump 一条 bash。
3. **Undo 日志。** `rm` 默认走废纸篓；rename/move/copy 记映射，栏里一键撤销上一次任务。
4. **Skills（Markdown 配方）。** 社区可贡献：`heic-to-jpg`、`podcast-loudnorm`、`pdf-split`、`batch-rename-exif`。Agent 按选中文件类型加载相关 skill。
5. **本地优先路由。** 有 Apple Foundation Models 或本机小模型时，先做意图分类 + Instant 匹配；只有复杂请求才打云端。
6. **中英一等。** IME、提示词、摘要、错误文案 zh-Hans + en。
7. **任务队列。** ffmpeg 长任务可并行，进度在栏里，完成后选中新文件。
8. **永不覆盖。** 默认 `file_1.mp4` 而不是踩掉原文件；原件默认保留。
9. **CLI。** `understage --here "转成 mp4"` 方便脚本和 Alfred。
10. **不做内容幻觉。** 「按内容分类照片」只在用户显式开视觉/本地 CLIP 时启用，否则走 EXIF/文件名/类型。

暂不做（除非你点名）：ForkLift 适配、iCloud Drive 深度同步语义、自动监视文件夹、语音输入、Windows。

---

## 4. 技术栈（推荐）

工程习惯：

- **原生 Swift 6 + SwiftUI + AppKit**（吸附窗口必须用 `NSPanel`）
- **XcodeGen** `project.yml`，不手改 `.xcodeproj`
- **macOS 15+**，Apple silicon 优先；有 Liquid Glass 则用，否则 fallback material
- **非 App Sandbox**（要 exec ffmpeg / 读任意用户文件）
- Hardened Runtime + 可选公证
- 权限：Accessibility（跟窗）、Automation/Finder（选中项与目录）、可选 Full Disk Access
- 许可：**MIT**
- Bundle ID 暂定 `design.understage.app`（可改）
- 本地化：`Localizable.xcstrings`（en + zh-Hans）

不用 Electron / Tauri：跟窗、焦点、Spaces、非激活输入框、AX 坐标在 WebView 里会长期打架。

工程结构草案：

```
Understage/
  README.md LICENSE Makefile project.yml
  App/                 # @main, entitlements, assets
  Sources/
    Docking/           # AX 跟窗、每窗口一条 NSPanel
    FinderBridge/      # ScriptingBridge：target + selection
    Context/           # MIME、尺寸、时长、git、芯片 UI
    Instant/           # 解析器 + 内置动作
    Predict/           # 命令预演 / 风险分级
    Agent/             # 计划、工具循环、follow-up session
    Execute/           # Process、cwd、超时、取消、进度
    Vendors/           # OpenAI-compat / Anthropic / Google / Ollama / LM Studio / Apple FM
    Skills/            # 内置 + 用户 ~/Library/Application Support/Understage/Skills
    History/           # 任务、undo journal
    UI/                # 栏、预览、设置、onboarding
  Tests/
  docs/PLAN.md docs/STATUS.md
```

---

## 5. Finder 吸附（最难的平台层）

参考 FinderNav 一类工具的机制，不注入 Finder：

- 每个可见 Finder 窗口对应一个 borderless `NSPanel`（`.floating`，可非激活，输入时激活）。
- `AXObserver`：窗口移动/缩放/最小化/关闭/Space 切换。
- 用窗口 bounds + pid 对齐 ScriptingBridge 的 `Finder window`，读 `target` 和 `selection`。
- 栏宽 = Finder 内容宽，贴在窗口下沿；多显示器、分屏、Stage Manager、Desktop（无窗口时一条桌面栏）都要测。
- Finder 不在前台且栏未聚焦 → 隐藏。全局快捷键开关。
- 标签页：AppleScript 把 tab 也叫 window，用 bounds 聚类，避免一条窗口 duplicating 多条栏。
- 选中变化：轮询 ScriptingBridge（~200ms）或监听 Finder 的 selection-changed 通知（若可用）。

Onboarding：逐步要 Accessibility、Automation，失败时栏显示「需要权限」而不是静默死掉。

---

## 6. 安全模型（必须先于 Agent）

生成/执行任何命令前走同一条管道：

1. **静态拒绝**：`sudo`、`rm -rf /`、写 `~/.ssh`、`diskutil`、`launchctl`、管道下载执行、任意 osascript 键鼠。
2. **工作区**：默认只能碰「当前 Finder 目录 ∪ 选中项 ∪ 用户在预览里确认的目标路径」。
3. **删除 = 废纸篓**，除非用户写明「永久删除」且二次确认。
4. **网络**：`curl`/`scp`/`rclone` 一律确认。
5. **Predict**：解析管道、重定向、循环，列出将创建/覆盖/移动/删除的路径。无法预演 → 强制确认。
6. **Auto-run 策略**（设置）：只读信息默认自动；创建新文件可自动；覆盖/移动/删除/出网永远确认。
7. **无 root、无提权。**

Agent 模式同样走这条管道：每个 `run` 工具调用都是一次 Predict + 策略，而不是把整个脚本一次性放行。

---

## 7. AI vendors

统一 `ChatProvider`：messages + 可选 tools + streaming。

开箱：

| 类型 | 后端 |
|---|---|
| 云端 | OpenAI、Anthropic、Google、xAI、Mistral、DeepSeek、OpenRouter（一个入口覆盖很多模型） |
| 兼容 | 任意 OpenAI-compatible base URL + key |
| 本地 | Ollama `:11434`、LM Studio `:1234`，启动时探测 |
| 系统 | macOS 26+ Apple Foundation Models（意图分类 / 简单 Command，不适合长 ffmpeg 脚本时自动升级） |

密钥进 Keychain，不进 UserDefaults、不进日志。设置里可按「速度 / 质量 / 本地」设默认，栏上可临时换模型。

提示词策略：给模型的是 **选中文件的结构化清单**（路径、类型、尺寸、时长、页数），不是让模型自己 `ls`。Instant 未命中时，few-shot 里塞同类成功命令。

---

## 8. Instant Actions 与内置工具

MVP 解析器覆盖（中英同义）：

- 转换：`jpg` `png` `webp` `heic` `mp4` `mp3` `wav` `gif` `pdf` `txt` `docx`
- 信息：`大小` `分辨率` `编码` `帧率` `时长` `词数` `行数` `路径` `类型`
- 管理：`zip` `unzip` `副本` `废纸篓` `打开终端` `复制路径`
- 选择：`选中所有 pdf`、`选中最后一个 jpg`
- 媒体：`1080p`、`720p`、`提取音频`、`去音频`

缺工具时：**按需安装**（检测 Homebrew，提示 `brew install ffmpeg`），不要把 ffmpeg 打进 14MB 的 app 里。内置用系统自带的优先：`sips`、`afconvert`、`textutil`、`qlmanage`。

---

## 9. UI

- 默认一条矮栏：左文件芯片（可点掉某个选中项）+ 输入 + 右模型指示。
- 回车后展开：生成的命令 / Predict 摘要 / 确认按钮 / 流式输出 / 进度。
- 长任务不阻塞输入：可再开一条任务。
- Ideas 面板：按当前选中类型给建议（选中视频 → 转码/抽音频/GIF/合并）。
- 设置：vendor、Auto-run、快捷键、Rules、Skills 目录。
- 菜单栏图标：权限状态、队列、打开设置。

视觉：跟 Finder 同宽、低对比、系统字体；深浅色跟随；不要做成 ChatGPT 气泡。

---

## 10. 里程碑

### M0 — Spike（批准后立刻做，1–2 天）

最小可运行 app：菜单栏常驻 + 一条吸附栏。

要证明的事：

- 每个可见 Finder 窗口底下贴一条 `NSPanel`，移动/缩放/切 Space 跟得上，不抢 Finder 焦点
- ScriptingBridge 读到该窗口的 `target` 和 `selection`，栏上显示路径和文件芯片
- 多窗口、Finder 标签、Desktop、Stage Manager、外接屏：在 `docs/spikes/S0-finder-dock.md` 写实测
- 无 Accessibility / 无 Automation 时有明确 onboarding，而不是静默空白
- 中文输入法能在栏里打字（Substage 1.0.2 才修好 CJK）

成功标准：打开两个 Finder 窗口，各自选不同文件，两条栏显示各自的选中项，拖窗口栏不脱落。

失败则停，不开始 Instant / LLM。

### M1 — 可日常使用的栏（无云端也可）

- 权限 onboarding
- Instant Actions + 本机工具检测
- 命令预览 + 确认 + 执行 + 取消
- 完成后 Reveal / 选中新文件
- 历史

### M2 — Vendors + Predict

- Provider 抽象 + Keychain
- OpenAI-compat + Anthropic + Ollama/LM Studio
- Predict 风险分级 + Auto-run
- 中英提示与摘要

### M3 — Agent + Skills + Undo

- 工具循环、follow-up session（按 Finder 路径记短期记忆）
- 内置 skills（ffmpeg / 重命名 / 归档）
- Undo journal
- 任务队列与进度

### M4 — 打磨

- Rules、Favorites、Ideas 面板
- Apple Foundation Models 路由
- CLI、Homebrew cask、Sparkle 或 `gh` 发布
- 桌面栏、Smart Folder 行为

---

## 11. 测试与验收

- 单元：Instant 解析、Predict 路径提取、vendor 请求编码、undo 映射
- 权限失败路径
- 手动矩阵（真机）：单窗口 / 多窗口 / 多屏 / Stage Manager / 中文输入法 / 长 ffmpeg / 无 ffmpeg / Ollama 离线
- 安全回归：生成 `sudo`、写出工作区、覆盖原文件 必须被拦住

M0/M1 的成功标准：在真实 Finder 里选中一张图，输入 `jpg`，下一秒同目录出现转换结果且原图还在。

---

## 12. 风险

- AX 跟窗在 macOS 新版本会碎，要隔离成 `Docking` 模块并准备轮询 fallback
- AppleScript 选中项在多标签/Smart Folder 上不可靠（Substage 1.0 才修好）
- 本地小模型写复杂 ffmpeg 容易错 → Instant + skill 模板优先于自由生成
- 非沙盒 + 执行任意命令 = 安全审查的焦点，文档必须写清威胁模型
- 公证与 Accessibility 对开源分发很烦，GitHub Releases + `xattr -cr` 说明要写进 README
