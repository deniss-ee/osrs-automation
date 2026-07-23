; ============================================================
; v7 micro 25 - gather-bank-loop (GatherBankLoop)
;
; Generalized from v6 motherlode2.ahk's RunFullLoop/FullCycle/MineLoop
; shape (confirmed live there across many mine->hopper->sack->bank->
; return laps). GatherBankLoop itself is deliberately thin - see
; Lib\Steps.ahk's header comment above it for why the "cut gathering
; short on a banking stall" policy lives INSIDE a bot's own gather
; closure, not in this composite.
;
; This micro reuses two already-confirmed composites as its gather/bank
; closures instead of building new test scaffolding:
;   gather = TrackAndClick (micro 21) until a cheap slot fills
;   bank   = DepositAllToBank + RunRestockPlan (micro 24)
; so what's actually being validated here is ONLY the new outer loop -
; does it correctly repeat gather->bank for maxCycles, stop cleanly the
; first time either closure fails, and remain F6-interruptible mid-cycle?
;
; WHAT IT DOES
;   F5  = run GatherBankLoop for MAX_CYCLES cycles (gather until
;         GATHER_UNTIL_SLOT fills, then bank via the marker/deposit/
;         restock config below)
;   F6  = request stop (interrupts instantly, mid-gather or mid-bank)
;   Esc = exit the script
;
; LIVE CONFIRM:
;   1. Put a TARGET_COLORS marker near REF_X/REF_Y, run F5 - confirm
;      cycle 1 gathers (TrackAndClick clicks it) until GATHER_UNTIL_SLOT
;      fills, then banks (marker+deposit click, confirm+restock), then
;      cycle 2 starts automatically - all the way to MAX_CYCLES.
;   2. Press F6 mid-gather - confirm it stops immediately, logging which
;      cycle it was on.
;   3. Let a bank step fail (e.g. hide the deposit image) - confirm the
;      whole loop stops cleanly and logs "bank failed on cycle N."
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "25-gather-bank-loop"

; ======= EDIT THESE FOR YOUR TEST =======================================
; --- Gather phase (TrackAndClick, same shape as micro 21) ---
TARGET_COLORS := [0x56FF50, 0x00B809]
COLOR_TOL := 5
BLOCK_W := 55
BLOCK_H := 55
VERIFY_PERCENT := 100

REF_X := CHAR_X
REF_Y := CHAR_Y
ACQUIRE_RADII := [ACQUIRE_PADDING_SMALL, ACQUIRE_PADDING_LARGE]
gameZone := GameZoneRegion()

TRACK_RADIUS_PX := 64
MAX_DRIFT_PX    := 32
STABLE_TICKS_REQUIRED := 2
MOVE_TOLERANCE_PX     := 8
CLICK_COOLDOWN_MS     := 1500
RECLICK_AFTER_MS      := 3000
CLICK_USE_CTRL        := true
POST_CLICK_SETTLE_MS  := 100

; Cheap until-condition for testing - fill this slot to end one gather
; phase without grinding a real full inventory.
GATHER_UNTIL_SLOT := 2

GATHER_PROGRESS_TIMEOUT_MS := 60000
GATHER_OVERALL_TIMEOUT_MS  := 300000

; --- Bank phase (DepositAllToBank + RunRestockPlan, same shape as micro 24) ---
; MARKER_ZONE picks how markerRegion (below) gets built - uncomment
; EXACTLY ONE of these three lines, comment out the other two (see
; Lib\Find.ahk's SearchZone doc). This is a single object literal per
; mode, not separate X/Y/W/H globals conditionally referenced - AHK v2's
; "variable never assigned" check scans the WHOLE file regardless of
; which branch actually runs, so a commented-out MARKER_AREA_X still got
; flagged even though the "area" branch never executed. An object
; literal's fields aren't separate variables, so there's nothing left
; for that check to flag.
MARKER_ZONE := {fixed: "area", x: 1482, y: 280, w: 43, h: 47, marginPx: 0}
; MARKER_ZONE := {mode: "area", x: 693, y: 229, w: 708, h: 636, marginPx: 0}
; MARKER_ZONE := {mode: "fixed", x: 1044, y: 928, w: 15, h: 15, marginPx: 0}

MARKER_COLORS := [0xFFB232]
MARKER_TOL := 5
MARKER_BLOCK_W := 15
MARKER_BLOCK_H := 15
MARKER_WAIT_TIMEOUT_MS := 15000

DEPOSIT_IMAGE_PATH := A_ScriptDir "\..\Images\deposit-bank.png"
DEPOSIT_TOL := 5
DEPOSIT_TRANS_COLOR := "0x00FF00"
DEPOSIT_WAIT_TIMEOUT_MS := 10000

RESTOCK_PLAN := [
    [1, 1]
]

BANK_CONFIRM_TIMEOUT_MS := 10000
POLL_MS := 100

; How many full gather+bank cycles this test run does before stopping on
; its own (a real bot leaves GatherBankLoop's maxCycles at 0 and relies
; on F6/failure instead - see Lib\Steps.ahk's doc comment).
MAX_CYCLES := 2
; ========================================================================

markerRegion := SearchZone(MARKER_ZONE)

; The deposit-all button IS a genuinely fixed Lib global position
; (standard #17) - always "fixed" mode, no per-script switch needed.
depositRegion := SearchZone({
    mode: "fixed", x: BANK_DEPOSIT_IMAGE_X, y: BANK_DEPOSIT_IMAGE_Y,
    w: BANK_DEPOSIT_IMAGE_W, h: BANK_DEPOSIT_IMAGE_H, marginPx: 0
})

F5:: RunLoop()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

GatherOnce() {
    global gameZone

    Say("micro25: gathering until slot " GATHER_UNTIL_SLOT " fills")

    UntilSlotFull() {
        return SlotFull(GATHER_UNTIL_SLOT)
    }

    return TrackAndClick({
        colors: TARGET_COLORS, tol: COLOR_TOL, blockW: BLOCK_W, blockH: BLOCK_H,
        verifyPercent: VERIFY_PERCENT,
        refX: REF_X, refY: REF_Y, acquireRadii: ACQUIRE_RADII, region: gameZone,
        trackRadius: TRACK_RADIUS_PX, maxDriftPx: MAX_DRIFT_PX,
        stableTicks: STABLE_TICKS_REQUIRED, moveTolerancePx: MOVE_TOLERANCE_PX,
        cooldownMs: CLICK_COOLDOWN_MS, reclickAfterMs: RECLICK_AFTER_MS,
        ctrl: CLICK_USE_CTRL, postClickSettleMs: POST_CLICK_SETTLE_MS,
        until: UntilSlotFull,
        timeoutMs: GATHER_OVERALL_TIMEOUT_MS, progressTimeoutMs: GATHER_PROGRESS_TIMEOUT_MS,
        pollMs: POLL_MS
    })
}

BankOnce() {
    Say("micro25: banking")

    ConfirmSlotEmpty() {
        return !SlotFull(1)
    }

    deposited := DepositAllToBank({
        markerColors: MARKER_COLORS, markerTol: MARKER_TOL,
        markerBlockW: MARKER_BLOCK_W, markerBlockH: MARKER_BLOCK_H,
        markerRegion: markerRegion,
        markerWaitTimeoutMs: MARKER_WAIT_TIMEOUT_MS,
        depositImagePath: DEPOSIT_IMAGE_PATH, depositImageW: BANK_DEPOSIT_IMAGE_W, depositImageH: BANK_DEPOSIT_IMAGE_H,
        depositTol: DEPOSIT_TOL, depositTransColor: DEPOSIT_TRANS_COLOR,
        depositRegion: depositRegion,
        depositClickX: CenterX(BANK_DEPOSIT_IMAGE_X, BANK_DEPOSIT_IMAGE_W),
        depositClickY: CenterY(BANK_DEPOSIT_IMAGE_Y, BANK_DEPOSIT_IMAGE_H),
        depositWaitTimeoutMs: DEPOSIT_WAIT_TIMEOUT_MS,
        confirmCondition: ConfirmSlotEmpty, confirmTimeoutMs: BANK_CONFIRM_TIMEOUT_MS,
        ctrl: CLICK_USE_CTRL, pollMs: POLL_MS,
        label: "micro25"
    })
    if (!deposited)
        return false

    Say("micro25: restocking " RESTOCK_PLAN.Length " slot(s)")
    RunRestockPlan(RESTOCK_PLAN, CLICK_USE_CTRL)
    return true
}

RunLoop() {
    global g_StopRequested
    g_StopRequested := false

    Say("micro25: starting GatherBankLoop (maxCycles=" MAX_CYCLES ")")

    t0 := A_TickCount
    try {
        result := GatherBankLoop({
            gather: GatherOnce,
            bank: BankOnce,
            maxCycles: MAX_CYCLES,
            label: "micro25"
        })
    } catch BotStopped {
        Say("micro25: STOPPED by F6 after " (A_TickCount - t0) " ms")
        return
    }
    elapsedMs := A_TickCount - t0

    msg := result
        ? "DONE - " MAX_CYCLES " cycle(s) completed (" elapsedMs " ms)"
        : "FAILED - gather or bank step failed (" elapsedMs " ms, see log)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=run GatherBankLoop  F6=request stop  Esc=exit."
    . " Targets=" JoinMsg(TARGET_COLORS, "/", HexColor) " gatherUntilSlot=" GATHER_UNTIL_SLOT
    . " maxCycles=" MAX_CYCLES)
ToolTip("micro 25 ready - F5 to run", 20, 20)
