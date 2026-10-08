; start-menu-reveal -- raise the Zebar bar over a fullscreen app while the Start menu is open.
;
; The bar is a zOrder "normal" window, so a fullscreen app covers it. Windows' own taskbar comes
; up over a fullscreen app when Start (or Search, or a taskbar flyout) opens; this does the same
; for the bar: on every foreground change it checks whether the new foreground window belongs to
; one of the shell hosts below, and if so makes every bar window TOPMOST; as soon as the
; foreground moves anywhere else the bar is made NOTOPMOST again, so the returning fullscreen app
; covers it as before. Event-driven (SetWinEventHook), no polling.
;
; Run with /debug to log each transition to %LOCALAPPDATA%\overline-zebar\start-menu-reveal.log.

#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon
Persistent

BAR_TITLE := "Zebar - mushfikurr.overline-zebar / main"   ; every monitor's bar has this title
SHELL_HOSTS := Map(
    "StartMenuExperienceHost.exe", 1,   ; Start
    "SearchHost.exe", 1,                ; Search (Win+S, typing in Start)
    "ShellExperienceHost.exe", 1,       ; notification centre / quick settings / calendar flyouts
    "ShellHost.exe", 1                  ; quick settings on newer Windows 11 builds
)

DEBUG := false
for arg in A_Args
    if (arg = "/debug")
        DEBUG := true
LOG_FILE := EnvGet("LOCALAPPDATA") "\overline-zebar\start-menu-reveal.log"
if DEBUG
    DirCreate(EnvGet("LOCALAPPDATA") "\overline-zebar")

HWND_TOPMOST := -1, HWND_NOTOPMOST := -2
SWP_FLAGS := 0x0001 | 0x0002 | 0x0010   ; NOSIZE | NOMOVE | NOACTIVATE

raised := false

Log(msg) {
    global DEBUG, LOG_FILE
    if DEBUG
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " msg "`n", LOG_FILE, "UTF-8")
}

SetBarTopmost(topmost) {
    global raised, BAR_TITLE, HWND_TOPMOST, HWND_NOTOPMOST, SWP_FLAGS
    if (topmost = raised)
        return
    raised := topmost
    count := 0
    for hwnd in WinGetList(BAR_TITLE " ahk_exe zebar.exe") {
        DllCall("SetWindowPos", "ptr", hwnd, "ptr", topmost ? HWND_TOPMOST : HWND_NOTOPMOST
            , "int", 0, "int", 0, "int", 0, "int", 0, "uint", SWP_FLAGS)
        count++
    }
    Log((topmost ? "raise" : "lower") " " count " bar window(s)")
}

OnForeground(hook, event, hwnd, idObject, idChild, thread, time) {
    global SHELL_HOSTS
    try exe := WinGetProcessName(hwnd)
    catch
        exe := ""
    Log("foreground " exe)
    SetBarTopmost(SHELL_HOSTS.Has(exe))
}

; EVENT_SYSTEM_FOREGROUND = 3; WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS = 0x2
global hookCallback := CallbackCreate(OnForeground, "F", 7)
global hook := DllCall("SetWinEventHook", "uint", 3, "uint", 3, "ptr", 0, "ptr", hookCallback
    , "uint", 0, "uint", 0, "uint", 0x2, "ptr")
if !hook {
    Log("SetWinEventHook failed")
    ExitApp(1)
}
Log("started")

OnExit((*) => (SetBarTopmost(false), DllCall("UnhookWinEvent", "ptr", hook)))
