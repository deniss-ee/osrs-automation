; ============================================================
; v7 micro 24 - deposit + restock (DepositAllToBank + RunRestockPlan)
;
; Port from v6 Lib\Steps.ahk, with two v7 contract changes:
; markerClickOffsetY is GONE (no click-offset compensation anywhere in
; v7), and markerColors is now an array (the v7 standard). Also adds
; FindAndClickImage back to Steps.ahk (deliberately not ported earlier
; for lack of a confirmed caller - DepositAllToBank's deposit-image
; click is exactly that caller) and BANK_GRID/BankSlotCenter to
; Lib\Inv.ahk (a separate grid from the player's own inventory,
; single-row only - v6's own measured limit, carried over as-is).
;
; DEPOSIT position ONLY comes from Lib (BANK_DEPOSIT_IMAGE_*,
; Lib\Find.ahk) - the deposit-all PNG button sits at the same fixed
; screen position no matter which bot opens a bank, so its search box
; is EXACT (marginPx=0, same convention as micro 07/16's fixed-position
; image search - no slack needed, a truly fixed point never drifts).
; The MARKER (deposit-box color block) is NOT fixed like that - it's a
; per-script position/color, same as micro 11's marker config, since it
; can differ per bank location, so IT still has its own MARKER_MARGIN_PX
; (default 0, same as every other micro's MARGIN_PX - raise only if
; camera drift while walking toward the bank turns out to need slack).
;
; MARKER click is PINNED (clickX/clickY = the measured corner's own
; computed center, same pattern v6's crafting.ahk/smithing.ahk used):
; the search still confirms something matching is actually visible
; nearby, but the click always lands at the corner's own center, never
; the found position - a search region can't guarantee the match it
; finds is centered exactly on the real button.
;
; RESTOCK_PLAN is a list of [slot, clicks] pairs (same shape v6's
; crafting.ahk/smithing.ahk used) - add/remove entries to restock
; multiple bank slots with different click counts in one pass.
;
; WHAT IT DOES
;   F5  = DepositAllToBank: click the pinned deposit-box marker
;         (MARKER_*), wait for the pinned deposit-all image (DEPOSIT_*)
;         to appear nearby, click it, then confirm slot 1 emptied
;   F7  = RunRestockPlan: walk RESTOCK_PLAN, clicking each [slot,
;         clicks] entry's bank slot that many times in a row
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   Esc = exit the script
;
; LIVE CONFIRM: with the bank interface open and slot 1 holding an
; item, press F5 - confirm the marker gets clicked, the deposit-all
; image gets found+clicked, and slot 1 is confirmed empty afterward.
; Then press F7 with real withdrawable items in RESTOCK_PLAN's slots -
; confirm each slot gets clicked its configured number of times, in order.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "24-deposit-all"

; ======= EDIT THESE FOR YOUR TEST =======================================
; Bank/deposit-box marker - fully per-script (color, position, size all
; local to this bot - a different bank location can have a different
; marker entirely). Same corner+size convention as micro 06/11.
MARKER_COLORS := [0xCC5D02]
MARKER_TOL := 5
MARKER_BLOCK_W := 33
MARKER_BLOCK_H := 33
MARKER_X := 1044
MARKER_Y := 928
MARKER_MARGIN_PX := 0   ; 0 by default like every other micro's MARGIN_PX - raise only if needed
MARKER_WAIT_TIMEOUT_MS := 15000

; The "deposit all" image - path/tol/timeout stay per-script, but
; POSITION comes from Lib\Find.ahk's BANK_DEPOSIT_IMAGE_X/Y/W/H (the
; deposit-all PNG button is fixed on this setup - see that file's
; note). No margin - a truly fixed point needs no slack (exact box,
; same as micro 07/16).
DEPOSIT_IMAGE_PATH := A_ScriptDir "\..\Images\deposit-bank.png"
DEPOSIT_TOL := 5
DEPOSIT_TRANS_COLOR := "0x00FF00"
DEPOSIT_WAIT_TIMEOUT_MS := 5000

CLICK_USE_CTRL := true
CONFIRM_TIMEOUT_MS := 10000
POLL_MS := 100

; Restock plan - list of [slot, clicks] pairs, same shape v6's
; crafting.ahk/smithing.ahk used. Add/remove entries freely.
RESTOCK_PLAN := [
    [1, 3],
    [2, 1]
]
; ========================================================================

markerRegion := RegionAround(MARKER_X, MARKER_Y, MARKER_BLOCK_W, MARKER_BLOCK_H, MARKER_MARGIN_PX)
depositRegion := RegionAround(BANK_DEPOSIT_IMAGE_X, BANK_DEPOSIT_IMAGE_Y,
    BANK_DEPOSIT_IMAGE_W, BANK_DEPOSIT_IMAGE_H, 0)

F5:: RunDeposit()
F7:: RunRestock()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunDeposit() {
    global g_StopRequested
    g_StopRequested := false

    Say("micro24: starting deposit")

    ConfirmSlotEmpty() {
        return !SlotFull(1)
    }

    t0 := A_TickCount
    try {
        result := DepositAllToBank({
            markerColors: MARKER_COLORS, markerTol: MARKER_TOL,
            markerBlockW: MARKER_BLOCK_W, markerBlockH: MARKER_BLOCK_H,
            markerRegion: markerRegion,
            markerClickX: CenterX(MARKER_X, MARKER_BLOCK_W),
            markerClickY: CenterY(MARKER_Y, MARKER_BLOCK_H),
            markerWaitTimeoutMs: MARKER_WAIT_TIMEOUT_MS,
            depositImagePath: DEPOSIT_IMAGE_PATH, depositImageW: BANK_DEPOSIT_IMAGE_W, depositImageH: BANK_DEPOSIT_IMAGE_H,
            depositTol: DEPOSIT_TOL, depositTransColor: DEPOSIT_TRANS_COLOR,
            depositRegion: depositRegion,
            depositClickX: CenterX(BANK_DEPOSIT_IMAGE_X, BANK_DEPOSIT_IMAGE_W),
            depositClickY: CenterY(BANK_DEPOSIT_IMAGE_Y, BANK_DEPOSIT_IMAGE_H),
            depositWaitTimeoutMs: DEPOSIT_WAIT_TIMEOUT_MS,
            confirmCondition: ConfirmSlotEmpty, confirmTimeoutMs: CONFIRM_TIMEOUT_MS,
            ctrl: CLICK_USE_CTRL, pollMs: POLL_MS,
            label: "micro24"
        })
    } catch BotStopped {
        Say("micro24: STOPPED by F6 after " (A_TickCount - t0) " ms")
        return
    }
    elapsedMs := A_TickCount - t0

    msg := result
        ? "DONE - deposit confirmed (" elapsedMs " ms)"
        : "FAILED - marker/deposit missing or not confirmed (" elapsedMs " ms, see log)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

RunRestock() {
    global g_StopRequested
    g_StopRequested := false

    Say("micro24: restocking " RESTOCK_PLAN.Length " slot(s)")
    RunRestockPlan(RESTOCK_PLAN, CLICK_USE_CTRL)
    Say("micro24: restock done")
}

LogLine("Script loaded. F5=deposit all  F7=restock plan  F6=request stop  Esc=exit."
    . " Marker=" JoinMsg(MARKER_COLORS, "/", HexColor) " restockPlan=" RESTOCK_PLAN.Length " entries")
ToolTip("micro 24 ready - F5=deposit  F7=restock", 20, 20)
