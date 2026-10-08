# start-menu-reveal

Brings the bar up over a fullscreen app while the Start menu is open, the way Windows' own taskbar
comes up.

## Why a helper

The `main` widget is a `zOrder: "normal"` window, so a fullscreen app covers it. Zebar 3.1.1 cannot
change a widget's z-order at runtime, and a widget's webview cannot see which window is in the
foreground, so the bar cannot do this itself. Making the bar permanently `top_most` would put it over
every fullscreen game and video.

## What it does

`start-menu-reveal.ahk` (AutoHotkey v2) hooks `EVENT_SYSTEM_FOREGROUND` (`SetWinEventHook`, out of
context, no polling). On every foreground change it reads the new foreground window's process:

| Process | Shell surface |
|---|---|
| `StartMenuExperienceHost.exe` | Start (older Windows 11 builds) |
| `SearchHost.exe` | Start on build 26200 (measured 2026-10-08), and Search |
| `ShellExperienceHost.exe` | notification centre, calendar flyout |
| `ShellHost.exe` | quick settings on newer builds |

If it is one of those, every window titled `Zebar - mushfikurr.overline-zebar / main` owned by
`zebar.exe` is made `HWND_TOPMOST` (`SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE`). On the next
foreground change to anything else they are made `HWND_NOTOPMOST` again; the fullscreen app, being
re-activated, comes back on top of the bar as before. The bar windows are looked up on every
transition, so a Zebar restart needs nothing. On exit the bar is lowered if it was raised.

The title is the pack name plus widget name: if the pack is ever renamed, update `BAR_TITLE`.

## Install / remove

```powershell
.\install.ps1              # Startup-folder shortcut + start it now (idempotent)
.\install.ps1 -Uninstall   # remove the shortcut and stop it
```

Needs AutoHotkey v2 at `%LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey64.exe`.

## Debugging

Run it with `/debug` to log each foreground process and each raise/lower to
`%LOCALAPPDATA%\overline-zebar\start-menu-reveal.log`.
