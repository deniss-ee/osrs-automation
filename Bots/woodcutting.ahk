; ============================================================
; Woodcutting bot - chop either of two interchangeable tree colors
; near the player, bank when full, repeat.
;
; Built entirely from confirmed v8 composites: TrackAndClick (micro
; 11) for acquire/track/click, StepLoop (micro 10) for the
; chop->bank cycle with retry + session-break pacing, DepositAllToBank
; (micro 12, plus this bot's markerCtrl/depositCtrl/
; depositSearchDelayMs additions) for the bank flow.
;
; WHAT IT DOES
;   F5  = start the chop->bank loop
;   F6  = request stop
;   F12 = exit
;
; LIVE CONFIRM (before trusting a real unbounded session):
;   1. MAX_CYCLES := 2 first - watch one full chop->bank->chop cycle
;      complete cleanly.
;   2. Confirm both break points actually fire (1/3 odds each - bump
;      the chance to 1.0 temporarily to observe the pause itself,
;      then revert).
;   3. Confirm the ctrl split: the bank marker click should show the
;      "run" click style, the deposit button click should not.
;   4. Re-verify TRACK_RADIUS_PX/MAX_DRIFT_PX against your real tree
;      spacing (69x69 trees, not the 45x45 ones micro 11/12 used) -
;      standard #15: trackRadius must stay under half the gap to the
;      nearest same-colored tree, or tracking can jump between trees.
;   5. Only after all of the above: raise MAX_CYCLES to 0.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v8.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "woodcutting"

; ======= EDIT THESE FOR YOUR SETUP =======================================
TREE_TARGET := {colors: [0x00FF00, 0x00B809], tol: 5, w: 69, h: 69}
BANK_MARKER := {colors: [0xFF980A], tol: 5, w: 43, h: 43}
BANK_MARKER_REGION := GameZoneRegion()
MARKER_WAIT_TIMEOUT_MS := 15000
DEPOSIT_WAIT_TIMEOUT_MS := 15000
CONFIRM_TIMEOUT_MS := 5000
DEPOSIT_SEARCH_DELAY_MS := [1500, 3000]   ; before searching for the deposit button, randomized (1.5x longer per live feedback - felt too fast at [1250,2000])

; TrackAndClick tuning - proven starting values from micro 11/12 (which
; used 45x45 trees). RE-VERIFY trackRadius/maxDriftPx against your real
; 69x69 tree spacing before trusting this live (standard #15:
; trackRadius must stay under half the gap to the nearest same-colored
; tree, or tracking can jump between two different trees).
ACQUIRE_RADII := [160, 320]
TRACK_RADIUS_PX := 96
MAX_DRIFT_PX := 64
STABLE_TICKS_REQUIRED := 2
MOVE_TOLERANCE_PX := 4
RECLICK_AFTER_MS := [3000, 6000]

; "roughly every 5" = 1/5 chance, rolled fresh at every fresh tree
; acquisition (first tree of the run and every re-acquire after one
; depletes) - models "took a moment to spot the next tree"
ACQUIRE_DELAY_CHANCE := 0.2
ACQUIRE_DELAY_MS := [1000, 6000]

INVENTORY_FULL_SLOT := 28   ; last slot - the only reliable "totally full" signal
CONFIRM_EMPTY_SLOT := 28    ; confirm the deposit via the last slot emptying - slot 1 sits at the
                            ; grid edge next to UI chrome and can false-read as full (confirmed live)

; "roughly every 3 runs" = 1/3 chance, rolled fresh each time
BREAK_AFTER_FULL_CHANCE := 0.5
BREAK_AFTER_FULL_MS := [1000, 6000]     ; after inventory full, before banking
BREAK_AFTER_BANK_CHANCE := 0.5
BREAK_AFTER_BANK_MS := [1000, 6000]      ; after emptying the bank

STEP_RETRIES := 1
MAX_CYCLES := 0   ; bounded first test - raise to 0 for a real unbounded run

; Mechanical click-settle gaps (glide-arrival -> actual click, and the
; post-click pause TrackAndClick uses to avoid misreading depletion
; flicker) - Lib defaults these to 100ms/0ms, floored here to 300ms.
CLICK_SETTLE_MS := 300
POST_CLICK_SETTLE_MS := 300

; While idling (stable-tracking a tree, waiting for it to deplete):
; roughly 1-in-3 chance, checked at most once every 1500ms, to roam
; the cursor anywhere on screen for 1-3s (each leg's own distance and
; pace independently randomized - long hops and short ones, fast
; flicks and slow drifts). NOT YET LIVE-CONFIRMED - a differently-
; shaped prior version of this idea (v7's IdleWander) didn't feel
; right and was removed; watch this closely the first few times.
IDLE_WANDER_CHANCE := 0.20
IDLE_WANDER_CHECK_MS := 1500
IDLE_WANDER_DURATION_MS := [750, 2500]
; ==========================================================================

ChopStep() {
    ok := TrackAndClick({
        target: TREE_TARGET, refX: CHAR_X, refY: CHAR_Y,
        acquireRadii: ACQUIRE_RADII, region: GameZoneRegion(),
        trackRadius: TRACK_RADIUS_PX, maxDriftPx: MAX_DRIFT_PX,
        stableTicks: STABLE_TICKS_REQUIRED, moveTolerancePx: MOVE_TOLERANCE_PX,
        reclickAfterMs: RECLICK_AFTER_MS, ctrl: true,
        clickSettleMs: CLICK_SETTLE_MS, postClickSettleMs: POST_CLICK_SETTLE_MS,
        acquireDelayChance: ACQUIRE_DELAY_CHANCE, acquireDelayMs: ACQUIRE_DELAY_MS,
        idleWanderChance: IDLE_WANDER_CHANCE, idleWanderCheckMs: IDLE_WANDER_CHECK_MS,
        idleWanderDurationMs: IDLE_WANDER_DURATION_MS,
        until: () => SlotFull(INVENTORY_FULL_SLOT),
        label: "woodcutting-chop"
    })
    if (ok)
        MaybeTakeBreak({chance: BREAK_AFTER_FULL_CHANCE, breakMs: BREAK_AFTER_FULL_MS, label: "woodcutting"})
    return ok
}

BankStep() {
    return DepositAllToBank({
        marker: BANK_MARKER, markerRegion: BANK_MARKER_REGION, markerWaitTimeoutMs: MARKER_WAIT_TIMEOUT_MS,
        markerCtrl: true, depositCtrl: false, depositSearchDelayMs: DEPOSIT_SEARCH_DELAY_MS,
        settleMs: CLICK_SETTLE_MS,
        wanderChance: IDLE_WANDER_CHANCE, wanderCheckMs: IDLE_WANDER_CHECK_MS, wanderDurationMs: IDLE_WANDER_DURATION_MS,
        deposit: {path: BANK_DEPOSIT_IMAGE_PATH, w: BANK_DEPOSIT_IMAGE_W, h: BANK_DEPOSIT_IMAGE_H,
            tol: 5, transColor: "0x00FF00"},
        depositRegion: BANK_DEPOSIT_IMAGE_REGION, depositWaitTimeoutMs: DEPOSIT_WAIT_TIMEOUT_MS,
        confirmCondition: () => !SlotFull(CONFIRM_EMPTY_SLOT), confirmTimeoutMs: CONFIRM_TIMEOUT_MS,
        label: "woodcutting-bank"
    })
}

RunWoodcutting() {
    return StepLoop({
        steps: [
            {name: "chop", run: ChopStep},
            {name: "bank", run: BankStep}
        ],
        retries: STEP_RETRIES, maxCycles: MAX_CYCLES,
        breakChance: BREAK_AFTER_BANK_CHANCE, breakMs: BREAK_AFTER_BANK_MS,
        label: "woodcutting"
    })
}

InstallBotHarness({
    run: RunWoodcutting,
    label: "woodcutting"
})
