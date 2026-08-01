; ============================================================
; v7 micro 02 - focus-guard diagnosis
;
; Port of v6 micro 13, confirmed live there: "ahk_exe RuneLite.exe"
; correctly tracks active/inactive across focus transitions on this
; setup (real process is RuneLite.exe, class SunAwtFrame - not a
; javaw/launcher wrapper). That's Lib\Core.ahk's GameActive() here.
;
; WHAT IT DOES
;   F5  = snapshot the CURRENT active window: exe name, class, title,
;         hwnd, whether each candidate match criterion would report
;         active RIGHT NOW, and what Lib\Core.ahk's GameActive() itself
;         returns. Tooltip + log.
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   Esc = exit the script
;
; LIVE CONFIRM: click into RuneLite, press F5 (should show ACTIVE for
; ahk_exe RuneLite.exe and GameActive()=ACTIVE), click into another
; window (e.g. this editor), press F5 again (should flip to not
; active / GameActive()=not active).
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("ToolTip", "Screen")

g_LogName := "02-focus-guard"

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
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunProbe() {
    global g_StopRequested
    g_StopRequested := false

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

LogLine("Script loaded. F5=probe active window  F6=request stop  Esc=exit")
ToolTip("micro 02 ready - click into RuneLite, then F5 to probe", 20, 20)
