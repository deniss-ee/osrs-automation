; ============================================================
; v7 micro 19 - pointer-walk slot classify-or-drop (VerifySlotsAndDrop)
;
; Generalized from v6 motherlode2.ahk's MineFullnessCheck (confirmed
; live there): a pointer walks inventory slots START_SLOT->END_SLOT in
; order. A still-empty slot at the pointer means "not done yet." Once
; the pointer's slot fills, it's classified against pay-dirt.png (the
; real reference image v6 used, 72x64 - matches INV_GRID's cell size
; exactly) - a match advances the pointer; a non-match (e.g. a gem)
; gets shift-dropped and the SAME slot is re-checked next tick.
;
; VerifySlotsAndDrop(opts) returns a MAKER function, not the check
; itself - the pointer is per-run state that must survive across many
; polled calls, so calling the maker once and reusing the returned
; closure is the whole point (see Lib\Steps.ahk's header comment).
;
; WHAT IT DOES
;   F5  = make a fresh VerifySlotsAndDrop closure (resets the pointer
;         to START_SLOT), then poll it every POLL_MS until it returns
;         true (all slots START_SLOT..END_SLOT confirmed pay-dirt) or
;         WAIT_TIMEOUT_MS elapses
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   Esc = exit the script
;
; LIVE CONFIRM: fill START_SLOT..END_SLOT with a mix of real pay-dirt
; and at least one non-pay-dirt item (e.g. a gem), press F5 - confirm
; the log shows each slot being checked in order, gems getting
; shift-dropped and re-checked (pointer doesn't advance), and the run
; reporting done once every slot from START_SLOT to END_SLOT holds
; confirmed pay-dirt. Also confirm a still-empty slot at the pointer
; just waits (no drop, no advance) rather than erroring.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "19-verify-slots"

; ======= EDIT THESE FOR YOUR TEST =======================================
START_SLOT := 2   ; skip slot 1 (matches v6's HAMMER_SLOT scenario - a
                  ; permanent tool that should never be checked/dropped)
END_SLOT := 5     ; small range for testing - not the full 28

; Reference image - same asset/size v6 used (72x64 matches INV_GRID's
; own cell size, so the search stays confined to one slot).
PAY_DIRT_IMAGE_PATH := A_ScriptDir "\..\Images\gold-bar.png"
PAY_DIRT_IMAGE_W := 72
PAY_DIRT_IMAGE_H := 64
PAY_DIRT_IMAGE_TOL := 5
PAY_DIRT_TRANS_COLOR := "0x00FF00"

DROP_SETTLE_MS := 100
WAIT_TIMEOUT_MS := 30000
POLL_MS         := 100
; ========================================================================

F5:: RunVerify()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunVerify() {
    global g_StopRequested
    g_StopRequested := false

    Say("VerifySlotsAndDrop: walking slots " START_SLOT ".." END_SLOT)

    checkNext := VerifySlotsAndDrop({
        startSlot: START_SLOT, endSlot: END_SLOT,
        path: PAY_DIRT_IMAGE_PATH, w: PAY_DIRT_IMAGE_W, h: PAY_DIRT_IMAGE_H,
        tol: PAY_DIRT_IMAGE_TOL, transColor: PAY_DIRT_TRANS_COLOR,
        dropSettleMs: DROP_SETTLE_MS, label: "micro19"
    })

    t0 := A_TickCount
    try {
        done := WaitUntil(checkNext, WAIT_TIMEOUT_MS, POLL_MS)
    } catch BotStopped {
        Say("micro19: STOPPED by F6 after " (A_TickCount - t0) " ms")
        return
    }
    elapsedMs := A_TickCount - t0

    msg := done
        ? "DONE - slots " START_SLOT ".." END_SLOT " all confirmed (" elapsedMs " ms)"
        : "TIMED OUT after " elapsedMs " ms - not all slots confirmed"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=verify slots  F6=request stop  Esc=exit."
    . " Range=" START_SLOT ".." END_SLOT " image=" PAY_DIRT_IMAGE_PATH)
ToolTip("micro 19 ready - F5 to verify slots " START_SLOT ".." END_SLOT, 20, 20)
