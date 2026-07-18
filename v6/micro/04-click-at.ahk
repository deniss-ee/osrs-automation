; ============================================================
; v6 micro 04 - single settled click
;
; Proves the click primitive every other block will use: move mouse to
; a fixed point, settle briefly (let the client register hover state),
; then click. Includes a Ctrl-held variant (OSRS "force run").
;
; No search involved - hardcode a point you can verify by eye (e.g. an
; inventory slot center, or a ground tile).
;
; WHAT IT DOES
;   F5  = plain click at TARGET_X, TARGET_Y
;   F7  = Ctrl-held click at TARGET_X, TARGET_Y (force-run click)
;   F6  = clear the tooltip
;   Esc = exit the script
;
; Syntax verified against AutoHotkey.pdf: Click() with no args clicks
; the left button at the mouse's current position; Click("Right") right
; -clicks at current position. Ctrl is NOT auto-released by Click (only
; Send auto-releases modifiers) - hold/release it explicitly, exactly
; as the docs' own Ctrl-click example does.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

; ======= EDIT THESE FOR YOUR TEST =======================================
TARGET_X := 1400   ; a point you can visually verify - inventory slot,
TARGET_Y := 696   ; ground tile, etc.
SETTLE_MS := 150   ; mechanical delay between move and click (v6 default)
; ========================================================================

F5:: ClickPlain()
F7:: ClickWithCtrl()
F6:: {
    ToolTip()
    LogLine("F6 pressed - tooltip cleared")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

ClickPlain() {
    LogLine("Click started: target=" TARGET_X "," TARGET_Y " settle=" SETTLE_MS "ms")
    t0 := A_TickCount

    MouseMove(TARGET_X, TARGET_Y, 5)
    Sleep(SETTLE_MS)
    Click()

    elapsedMs := A_TickCount - t0
    msg := "Clicked at " TARGET_X "," TARGET_Y " (" elapsedMs " ms incl. settle)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

ClickWithCtrl() {
    LogLine("Ctrl-click started: target=" TARGET_X "," TARGET_Y " settle=" SETTLE_MS "ms")
    t0 := A_TickCount

    Send("{Ctrl down}")
    MouseMove(TARGET_X, TARGET_Y, 5)
    Sleep(SETTLE_MS)
    Click()
    Sleep(SETTLE_MS)
    Send("{Ctrl up}")

    elapsedMs := A_TickCount - t0
    msg := "Ctrl-clicked (force-run) at " TARGET_X "," TARGET_Y " (" elapsedMs " ms incl. settle)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

; ---------- logging ----------

LogLine(msg) {
    static logDir := A_ScriptDir "\..\logs"
    static logPath := logDir "\04-click-at.log"
    if (!DirExist(logDir))
        DirCreate(logDir)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [04-click-at] " msg "`n", logPath)
}

LogLine("Script loaded. F5=click  F7=ctrl-click  F6=clear tooltip  Esc=exit. Target=" TARGET_X "," TARGET_Y)
ToolTip("micro 04 ready - F5 click / F7 ctrl-click", 20, 20)