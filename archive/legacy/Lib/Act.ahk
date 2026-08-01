; ============================================================
; v6 Lib\Act.ahk - the click primitive
;
; Byte-identical port of the canonical ClickAt shared across micros
; 04/05/08/11/12 (md5-verified during Stage 1's final audit). The only
; change from the micro versions: SETTLE_MS/CTRL_HOLD_MS are now local
; statics inside the function instead of script-level globals each
; micro had to declare - same values (100/100), just no longer
; something every caller needs to define. Per working rules, these are
; fixed mechanical constants, not per-bot tunables.
;
; useShift added (2026-07-21, Motherlode2's gem-drop step) - same
; down/hold/up mechanics as useCtrl, for exactly the same reason
; (Click() being synchronous doesn't mean the game client has
; processed the modifier yet). Purely additive: every existing
; positional call (ClickAt(x, y, CLICK_USE_CTRL)) is unaffected since
; useShift defaults false.
;
; PressKey is NOT here - no micro tested it, and no bot planned so far
; (Motherlode) needs it. Add it as its own micro when a bot that
; actually needs it (Firemaking/Smithing's "Press Space") comes up.
; ============================================================

ClickAt(x, y, useCtrl := false, useShift := false) {
    static SETTLE_MS := 100
    static CTRL_HOLD_MS := 100

    if (useCtrl)
        Send("{Ctrl down}")
    if (useShift)
        Send("{Shift down}")

    MouseMove(x, y, 5)
    Sleep(SETTLE_MS)
    Click()

    ; CTRL_HOLD_MS is load-bearing, not redundant with SETTLE_MS - a prior
    ; attempt to remove it broke force-run in-game. Click() being
    ; synchronous only means the OS input queue accepted the down/up
    ; pair; it says nothing about whether OSRS's own client (reading
    ; input on its own thread/tick) has processed it yet. Releasing
    ; Ctrl too soon risks the client seeing the click without the held
    ; modifier, so the character walks instead of runs. v5's production
    ; Click.ahk holds this same gap (ctrlHoldSettleMs, default 100 in
    ; every bot's .ini) for exactly this reason. Same reasoning applies
    ; to useShift.
    if (useCtrl) {
        Sleep(CTRL_HOLD_MS)
        Send("{Ctrl up}")
    }
    if (useShift) {
        Sleep(CTRL_HOLD_MS)
        Send("{Shift up}")
    }
}
