; ============================================================
; v6 micro 13 - focus-guard diagnosis
;
; v5's WindowFocus class guards every bot phase with
; `WinActive("ahk_exe RuneLite.exe")` - and it's been DISABLED in
; Woodcutting because it kept reporting "not active" even while
; RuneLite visibly had focus. This micro found it: reports the ACTIVE
; window's real exe/class/title next to what a few candidate criteria
; actually match, so the correct WinTitle criterion could be picked.
;
; CONFIRMED (v6\logs\13-focus-guard.log, 2026-07-19): the real
; foreground process on this setup is literally RuneLite.exe (class
; SunAwtFrame, not a javaw/launcher wrapper) - "ahk_exe RuneLite.exe"
; correctly tracked active/inactive across multiple focus transitions.
; That's now Lib\Core.ahk's GameActive().
;
; WHAT IT DOES
;   F5  = snapshot the CURRENT active window: exe name, class, title,
;         hwnd, whether each candidate match criterion would report
;         active RIGHT NOW, and what Lib\Core.ahk's GameActive() itself
;         returns. Tooltip + log.
;   F6  = clear the tooltip
;   Esc = exit the script
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("ToolTip", "Screen")

g_LogName := "13-focus-guard"

; ======= EDIT THESE FOR YOUR TEST =======================================
; Candidate match criteria to compare - add/edit if your setup differs
; (e.g. a different launcher class name).
CANDIDATES := Map(
    "ahk_exe RuneLite.exe", "ahk_exe RuneLite.exe",
    "ahk_exe javaw.exe", "ahk_exe javaw.exe",
    "title contains RuneLite", "RuneLite"
)
; ========================================================================

F5:: RunProbe()
F6:: {
    ToolTip()
    LogLine("F6 pressed - tooltip cleared")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunProbe() {
    hwnd := WinExist("A")
    if (!hwnd) {
        msg := "No active window detected"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }

    exeName := WinGetProcessName("ahk_id " hwnd)
    className := WinGetClass("ahk_id " hwnd)
    title := WinGetTitle("ahk_id " hwnd)

    lines := ["ACTIVE WINDOW: exe=" exeName " class=" className " title=`"" title "`" hwnd=" hwnd]
    LogLine(lines[1])

    for label, criterion in CANDIDATES {
        isActive := WinActive(criterion) ? true : false
        line := "  [" label "] WinActive(`"" criterion "`") = " (isActive ? "ACTIVE" : "not active")
        lines.Push(line)
        LogLine(line)
    }

    gameActiveLine := "  GameActive() = " (GameActive() ? "ACTIVE" : "not active")
    lines.Push(gameActiveLine)
    LogLine(gameActiveLine)

    msg := ""
    for i, line in lines
        msg .= (i = 1 ? "" : "`n") line
    ToolTip(msg, 20, 20)
}

LogLine("Script loaded. F5=probe active window  F6=clear tooltip  Esc=exit")
ToolTip("micro 13 ready - click into RuneLite, then F5 to probe", 20, 20)
