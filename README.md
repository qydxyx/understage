# Understage

Open-source Finder command bar. A strip docks under each Finder window, sees the current folder and selection, and runs Instant Actions, a predicted shell command, or a file agent.

## Requirements

- macOS 15 or later, Apple silicon
- [Xcode](https://developer.apple.com/xcode/) 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build

```bash
make gen
make build
make test
make run
```

Menu bar icon: rectangle with a filled bottom half. **Settings…** in that menu, or the gear on the Finder bar.

```bash
make cli          # Release CLI
make install      # copies `understage` to /usr/local/bin
make dist         # Release app + CLI
```

## Permissions

1. **Accessibility** — follow Finder window frames  
2. **Automation (Finder)** — read folder targets and selection  

## Use

- Instant: `jpg`, `zip`, `1080p`, `废纸篓`, `选中所有 pdf`
- Longer requests use your vendor (OpenAI-compatible, Anthropic, Ollama, LM Studio)
- Lightbulb on the bar: Ideas for the current selection  
- Star a successful result to save a Favorite  
- Settings → Rules: e.g. trigger `web`, instruction `export at 1000px wide`

```bash
understage jpg           # plan for Finder selection or cwd
understage --yes zip
```

Skills: `~/Library/Application Support/Understage/Skills/*.md`

## License

MIT. Understage is not affiliated with Selkie Design or Substage.
