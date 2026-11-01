# Understage

[English](README.md)

开源的访达命令栏。每扇访达窗口下方有一条命令栏，能看到当前文件夹和选中项，并执行 Instant Action、可预演的 shell 命令，或文件 Agent。

界面语言为英文和简体中文，跟随系统语言。命令本身中英都可以。

## 环境

- macOS 15 或更高，Apple 芯片
- [Xcode](https://developer.apple.com/xcode/) 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`

## 构建

```bash
make gen
make build
make test
make run
```

菜单栏图标是下半截填实的矩形。从该菜单打开**设置…**，或点命令栏上的齿轮。

```bash
make cli          # Release 版命令行
make install      # 把 understage 装到 /usr/local/bin
make dist         # Release 版 App 和命令行
make package      # 在 dist 之外再打出 dist/release 里的 dmg 和 zip
```

## 权限

1. **辅助功能** — 跟随访达窗口位置
2. **自动化（访达）** — 读取文件夹和选中项

## 使用

- Instant：`jpg`、`zip`、`1080p`、`废纸篓`、`选中所有 pdf`
- 更长的请求走你自己的服务商（OpenAI 兼容、Anthropic、Ollama、LM Studio）
- 命令栏上的灯泡：针对当前选中项的想法
- 给成功的结果加星，保存为收藏
- 设置 → 规则：例如触发词 `web`，指令 `export at 1000px wide`

```bash
understage jpg           # 为访达选中项或当前目录生成计划
understage --yes zip
```

技能文件：`~/Library/Application Support/Understage/Skills/*.md`

## 发布

版本号在 `project.yml` 的 `MARKETING_VERSION`。[`.github/workflows/release.yml`](.github/workflows/release.yml) 会在推送匹配的 tag 时构建 GitHub Release。每次发布都带这两个安装包：

- `Understage-<version>-macOS-arm64.dmg`
- `Understage-<version>-macOS-arm64.zip`

```bash
# MARKETING_VERSION 已是 1.2.0，并且该提交已在 main 上
git tag v1.2.0
git push origin main
git push origin v1.2.0
```

tag 必须和 `MARKETING_VERSION` 一致，否则工作流会停。安装包是临时签名。如果系统拦截第一次打开，请在访达里用快捷菜单打开。

## 许可

MIT。Understage 与 Selkie Design 或 Substage 无关。
