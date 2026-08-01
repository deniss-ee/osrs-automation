; ============================================================
; v8 micro 12 - Steps.ahk pt 4: DepositAllToBank, then the dress
; rehearsal (a real StepLoop chop->bank cycle, fail-safe engine
; driving real composites for the first time)
;
; Ported from v7 micros 24 (deposit-all) and 25 (gather-bank-loop),
; but the dress rehearsal here is new to v8: it wires TrackAndClick
; (micro 11) + DepositAllToBank (this micro) through Run.ahk's
; StepLoop with retries:1, and gives you an easy way to provoke a
; bank-step failure (F9 toggles a "sabotage" flag that makes
; DepositAllToBank's deposit-button search deliberately miss once)
; so you can WATCH a live retry happen, then watch a second failure
; produce a clean FAILED stop with the script still responding.
;
; WHAT IT DOES
;   F5  = DepositAllToBank alone: search + click MARKER, then search
;         + click DEPOSIT, confirm via !SlotFull(INVENTORY_FULL_SLOT)
;         (an optional gate-then-pin markerClick is documented in the
;         config block)
;   F6  = request stop
;   F8  = probe: RunRestockPlan against RESTOCK_PLAN
;   F9  = toggles SABOTAGE_NEXT_BANK - when true, the next bank
;         attempt inside the dress rehearsal deliberately searches a
;         1x1px region (guaranteed miss) instead of the real deposit
;         region, to simulate a missed click
;   F7  = the dress rehearsal: StepLoop({chop, bank}, retries: 1,
;         maxCycles: 2) - a real 2-step cycle. Toggle F9 before
;         pressing F7 to watch the bank step fail, retry fresh, and
;         (if you toggle F9 on again before the retry lands) fail a
;         second time -> FAILED, loop stops cleanly
;   F12 = exit
;
; LIVE CONFIRM:
;   1. F5 - marker click, deposit click, confirmed empty - matches
;      v7's proven deposit flow exactly.
;   2. F8 - restock plan clicks the right slots the right number of
;      times, each its own jittered click (not the same pixel N
;      times in a row).
;   3. F7 without ever pressing F9 - two clean chop->bank cycles,
;      maxCycles reached, true/DONE.
;   4. F7 WITH F9 toggled on before the bank step - watch "step
;      'bank' failed (attempt 1/2) - retrying fresh" in the log/
;      tooltip, then (since sabotage is a one-shot per toggle) the
;      retry succeeds - RunSteps returns true, cycle continues.
;   5. F7 with F9 toggled on twice in a row (before AND during the
;      retry window) - watch "FAILED after 2 attempt(s)", StepLoop
;      returns false, WrapHandler reports FAILED, script still
;      responds to F5/F7 again afterward.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v8.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "12-deposit-loop"

; ======= EDIT THESE FOR YOUR TEST =======================================
MARKER := {colors: [0xFF980A], tol: 5, w: 13, h: 13}
MARKER_REGION := GameZoneRegion()
MARKER_WAIT_TIMEOUT_MS := 15000
; Optional pin: the marker SEARCH still gates (v7's proven
; gate-then-pin semantics), the pin only overrides where the click
; lands - uncomment and add `markerClick: MARKER_CLICK` to the
; DepositAllToBank opts to use it.
; MARKER_CLICK := ClickTarget(1249, 712, 13, 13)

DEPOSIT_TARGET := {path: BANK_DEPOSIT_IMAGE_PATH, w: BANK_DEPOSIT_IMAGE_W, h: BANK_DEPOSIT_IMAGE_H,
    tol: 5, transColor: "0x00FF00"}
DEPOSIT_REGION := BANK_DEPOSIT_IMAGE_REGION
DEPOSIT_WAIT_TIMEOUT_MS := 15000
CONFIRM_TIMEOUT_MS := 5000

INVENTORY_FULL_SLOT := 28

RESTOCK_PLAN := [[1, 1], [2, 3]]

TREE_TARGET := {colors: [0x00FF00], tol: 5, w: 45, h: 45}
ACQUIRE_RADII := [160, 320]
TRACK_RADIUS_PX := 96
MAX_DRIFT_PX := 64
RECLICK_AFTER_MS := [3000, 6000]

DRESS_REHEARSAL_MAX_CYCLES := 2
DRESS_REHEARSAL_RETRIES := 1
; ==========================================================================

g_SabotageNextBank := false

RunDepositOnce() {
    return DepositAllToBank({
        marker: MARKER, markerRegion: MARKER_REGION, markerWaitTimeoutMs: MARKER_WAIT_TIMEOUT_MS,
        deposit: DEPOSIT_TARGET, depositRegion: DEPOSIT_REGION, depositWaitTimeoutMs: DEPOSIT_WAIT_TIMEOUT_MS,
        confirmCondition: () => !SlotFull(INVENTORY_FULL_SLOT), confirmTimeoutMs: CONFIRM_TIMEOUT_MS,
        label: "micro12"
    })
}

ProbeRestock() {
    return RunRestockPlan({plan: RESTOCK_PLAN, label: "micro12-restock"})
}

ToggleSabotage() {
    global g_SabotageNextBank
    g_SabotageNextBank := !g_SabotageNextBank
    Say("micro12: SABOTAGE_NEXT_BANK=" g_SabotageNextBank)
}

ChopStep() {
    return TrackAndClick({
        target: TREE_TARGET, refX: CHAR_X, refY: CHAR_Y,
        acquireRadii: ACQUIRE_RADII, region: GameZoneRegion(),
        trackRadius: TRACK_RADIUS_PX, maxDriftPx: MAX_DRIFT_PX,
        stableTicks: 2, moveTolerancePx: 4, reclickAfterMs: RECLICK_AFTER_MS,
        until: () => SlotFull(INVENTORY_FULL_SLOT),
        label: "micro12-chop"
    })
}

BankStep() {
    global g_SabotageNextBank
    if (g_SabotageNextBank) {
        g_SabotageNextBank := false
        Say("micro12: SABOTAGE armed - deposit button search will deliberately miss")
        return DepositAllToBank({
            marker: MARKER, markerRegion: MARKER_REGION, markerWaitTimeoutMs: MARKER_WAIT_TIMEOUT_MS,
            deposit: DEPOSIT_TARGET, depositRegion: [0, 0, 1, 1], depositWaitTimeoutMs: 500,
            confirmCondition: () => !SlotFull(INVENTORY_FULL_SLOT), confirmTimeoutMs: CONFIRM_TIMEOUT_MS,
            label: "micro12-bank-sabotaged"
        })
    }
    return RunDepositOnce()
}

RunDressRehearsal() {
    return StepLoop({
        steps: [
            {name: "chop", run: ChopStep},
            {name: "bank", run: BankStep, done: () => !SlotFull(INVENTORY_FULL_SLOT), doneTimeoutMs: CONFIRM_TIMEOUT_MS}
        ],
        maxCycles: DRESS_REHEARSAL_MAX_CYCLES, retries: DRESS_REHEARSAL_RETRIES, label: "micro12-rehearsal"
    })
}

InstallBotHarness({
    run: RunDepositOnce,
    label: "micro12",
    probe: ProbeRestock,
    extraHotkeys: [
        {key: "F7", handler: RunDressRehearsal, label: "dress-rehearsal"},
        {key: "F9", handler: ToggleSabotage, label: "toggle-sabotage"}
    ]
})
