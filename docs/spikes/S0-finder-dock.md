# S0 — Finder docking

Goal: prove a bar can stick under real Finder windows, show that window's folder and selection, and accept CJK input. No AI.

## How it works

- **Geometry:** Accessibility `AXWindow` position/size, converted from AX top-left to Cocoa bottom-left (`AXGeometry`).
- **Identity:** `_AXUIElementGetWindow` when present, else title+frame fallback.
- **Folder:** `AXDocument` on the window, else JXA `Finder.finderWindows().target().url()`.
- **Selection:** per-window `AXSelectedChildren` / `AXSelectedRows` (Finder's AppleScript `selection` is frontmost-only).
- **Placement:** flush under the window; overlay the bottom edge if that would sit under the Dock.
- **Permissions:** Accessibility for frames; Automation for JXA targets. Missing Accessibility shows one onboarding bar instead of nothing.
- **IME:** panel can become key; click in the field activates the app. Showing/moving uses `orderFrontRegardless` so tracking does not steal Finder focus.

## Manual matrix

Run `make run`, grant permissions, then:

| Case | Expected | Result |
|---|---|---|
| One Finder window | Bar under that window, folder name visible | |
| Two windows, different selections | Two bars, chips match each window | |
| Drag / resize | Bar stays attached | |
| Finder tabs | One bar per visible window, not per tab | |
| Desktop, no windows | One bottom bar on the main screen | |
| Click text field, type 中文 | Composition works, submit echoes on the right | |
| Switch to another app | Bars hide | |
| Stage Manager / extra display | Record what happens | |

## Build-time notes

- `xcodebuild` Debug **build succeeded** (macOS 27 SDK, arm64).
- Unit tests: 4/4 passed (Y-flip, bar below window, bar overlay when clipped, JXA title+size match).
- Live AX / Automation cannot be asserted in `xcodebuild test`. Grant Accessibility + Finder automation, then fill the matrix above.

## Known limits (expected for M0)

- Finder AppleScript `selection` is frontmost-only; per-window chips depend on AX selected rows. Icon/column/gallery views may return empty chips until the walker is extended.
- `_AXUIElementGetWindow` is a private HIServices symbol; geometry fallback still works if it is missing.
- Agent app (`LSUIElement`): look in the menu bar, not the Dock.
