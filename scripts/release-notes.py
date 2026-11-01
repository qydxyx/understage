#!/usr/bin/env python3
import sys

version = sys.argv[1]
print(
    f"""Understage {version} for macOS 15 or later, Apple silicon.

- `Understage-{version}-macOS-arm64.dmg` — drag Understage into Applications
- `Understage-{version}-macOS-arm64.zip` — zipped Understage.app

The build is ad-hoc signed. On first launch, open it from Finder with the shortcut menu if macOS blocks it.

适用于 macOS 15 及以上、Apple 芯片。

- `Understage-{version}-macOS-arm64.dmg` — 把 Understage 拖进应用程序
- `Understage-{version}-macOS-arm64.zip` — Understage.app 的 zip

安装包为临时签名。若系统拦截，请在访达中用快捷菜单打开。
"""
)
