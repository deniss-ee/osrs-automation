; ============================================================
;  ui.ahk - SHOWING YOU LITTLE STATUS MESSAGES
; ------------------------------------------------------------
;  ELI5: A "Tooltip" is that little yellow box that pops up near
;  your mouse/screen. We use it instead of a full window because
;  it's the simplest way to tell you what the bot is doing right
;  now ("Mining ore #1", "Inventory full", etc.) without getting
;  in the way of clicking on the game.
; ============================================================

#Requires AutoHotkey v2.0

; --------------------------------------------------------------
; ShowTip: draws the tooltip text in a fixed spot (right side of
; the screen, away from where we usually click) so it doesn't
; cover up the game while the bot is working.
; --------------------------------------------------------------
ShowTip(text) {
    x := A_ScreenWidth - 420
    y := 40
    ToolTip(text, x, y)
}

; --------------------------------------------------------------
; HideTip: clears the tooltip. Usually called a second or two
; after ShowTip via SetTimer(HideTip, -2000), so the message
; shows briefly then disappears on its own.
; --------------------------------------------------------------
HideTip() {
    ToolTip()
}
