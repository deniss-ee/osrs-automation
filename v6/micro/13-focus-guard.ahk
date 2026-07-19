; ============================================================
; v6 micro 13 - focus-guard diagnosis
;
; v5's WindowFocus class guards every bot phase with
; `WinActive("ahk_exe RuneLite.exe")` - and it's been DISABLED in
; Woodcutting (Bots\Woodcutting\woodcutting.ahk:71-77) because it kept
; reporting "not active" even while RuneLite visibly had focus. Root
; cause was never diagnosed. This micro finds it: report the ACTIVE
; window's real exe/class/title next to what "ahk_exe RuneLite.exe"
; actually matches, so the correct WinTitle criterion can be picked.
;
; Likely culprit: many RuneLite installs run through a launcher/JVM
; wrapper, so the real foreground process may be "javaw.exe" or similar,
; not literally "RuneLite.exe" - WinActive("ahk_exe RuneLite.exe") would
; then always report false with the game clearly focused.
;
; WHAT IT DOES
;   F5  = snapshot the CURRENT active window: exe name, class, title,
;         hwnd, and whether each of three candidate match criteria
;         (ahk_exe RuneLite.exe / ahk_class SunAwtFrame / title-substring
;         "RuneLite") would report active RIGHT NOW. Tooltip + log.
;   F6  = clear the tooltip
;   Esc = exit the script
;
; TEST IT: click into the RuneLite game window, press F5 - note the
; real exe/class/title and which candidate criteria say "ACTIVE". Then
; click into some OTHER window (browser, notepad) and press F5 again -
; confirm the same criteria now say "not active". Whichever criterion
; is ACTIVE-when-focused and NOT-active-when-unfocused, consistently,
; is the one that becomes GameActive() when this graduates to Lib.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

CoordMode("ToolTip", "Screen")

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

    msg := ""
    for i, line in lines
        msg .= (i = 1 ? "" : "`n") line
    ToolTip(msg, 20, 20)
}

; ---------- logging ----------

LogLine(msg) {
    static logDir := A_ScriptDir "\..\logs"
    static logPath := logDir "\13-focus-guard.log"
    if (!DirExist(logDir))
        DirCreate(logDir)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [13-focus-guard] " msg "`n", logPath)
}

LogLine("Script loaded. F5=probe active window  F6=clear tooltip  Esc=exit")
ToolTip("micro 13 ready - click into RuneLite, then F5 to probe", 20, 20)
