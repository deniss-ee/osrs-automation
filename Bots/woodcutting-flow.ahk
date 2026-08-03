; ============================================================
; Woodcutting bot with FLOW CLICKS - chop either of two interchangeable tree colors
; near the player, bank when full, repeat.
;
; NEW: Uses the continuous flow-click primitive (Act.ahk ClickAtFlow) instead
; of stop-settle-click sequences. Every click sweeps through the target with
; non-zero velocity (never a hard stop at the clicked pixel), tuned per click
; type (tree, bank marker, deposit button).
;
; Built entirely from confirmed v8 composites: TrackAndClick (micro
; 11) for acquire/track/click, StepLoop (micro 10) for the
; chop->bank cycle with retry + session-break pacing, DepositAllToBank
; (micro 12, plus this bot's markerCtrl/depositCtrl/
; depositSearchDelayMs additions) for the bank flow.
;
; WHAT IT DOES
;   F5  = start the chop->bank loop with flow clicks
;   F6  = request stop
;   F12 = exit
;
; LIVE CONFIRM (same as original + new flow-click checks):
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
;   5. NEW: Confirm tree clicks sweep away and don't land frozen on the
;      trunk pixel - smooth continuous motion through click point.
;   6. NEW: Confirm deposit button click feels natural - not like cursor
;      is "stuck" at the button for a pause.
;   7. Only after all of the above: raise MAX_CYCLES to 0.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v8.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "woodcutting-flow"

; ======= EDIT THESE FOR YOUR SETUP =======================================
TREE_TARGET := {colors: [0x00FF00, 0x00B809], tol: 5, w: 69, h: 69}
BANK_MARKER := {colors: [0xFF980A], tol: 5, w: 43, h: 43}
BANK_MARKER_REGION := GameZoneRegion()
MARKER_WAIT_TIMEOUT_MS := 15000
DEPOSIT_WAIT_TIMEOUT_MS := 15000
CONFIRM_TIMEOUT_MS := 5000
DEPOSIT_SEARCH_DELAY_MS := [500, 1000]

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
RECLICK_AFTER_MS := [2500, 5000]

; "roughly every 5" = 1/5 chance, rolled fresh at every fresh tree
; acquisition (first tree of the run and every re-acquire after one
; depletes) - models "took a moment to spot the next tree"
ACQUIRE_DELAY_CHANCE := 0.33
ACQUIRE_DELAY_MS := [1000, 5000]

INVENTORY_FULL_SLOT := 28
CONFIRM_EMPTY_SLOT := 28

; "roughly every 3 runs" = 1/3 chance, rolled fresh each time
BREAK_AFTER_FULL_CHANCE := 0.75
BREAK_AFTER_FULL_MS := [1000, 10000]
BREAK_AFTER_BANK_CHANCE := 0.5
BREAK_AFTER_BANK_MS := [1000, 5000]

STEP_RETRIES := 1
MAX_CYCLES := 2   ; start low for live confirmation of flow-click behavior

; Session length
HOUR_MS := 3600000
SESSION_LENGTH_MS := 3 * HOUR_MS

; MECHANICAL click-settle gaps (arrival->click gap only - no post-click
; dwell since flow takes care of the departure). Kept short since flow
; handles motion smoothness.
CLICK_SETTLE_MS := [15, 40]

; Deposit-button settle (same reasoning - kept short, flow does the work).
DEPOSIT_SETTLE_MS := [20, 60]

; Deposit distraction (pre-click reaction delay, orthogonal to flow).
DEPOSIT_DISTRACTED_CHANCE := 0.5
DEPOSIT_DISTRACTED_MS := [1000, 3000]

; === NEW: FLOW-CLICK CONFIGS ===
; These define the continuous glide-through-click behavior for each click
; type. flow: {chance: 0-1, distFrac: [min,max] (fraction of A_ScreenHeight),
; region: optional clamp}. When chance rolls, the click sweeps away from the
; target at a random distance (RandTri-weighted within distFrac range).

; Tree click: meaningful travel (0-25% of screen height), high confidence.
TREE_FLOW := {chance: 1.0, distFrac: [0, 0.25], region: GameZoneRegion()}

; Bank marker click: small drift (0-10% of screen height), reflexive click
; at a known fixed position doesn't need to travel far.
MARKER_FLOW := {chance: 1.0, distFrac: [0, 0.10], region: GameZoneRegion()}

; Deposit button click: very small drift (0-5% of screen height), UI button
; in the bank interface. Small distance to avoid clicking nearby buttons
; accidentally.
DEPOSIT_FLOW := {chance: 1.0, distFrac: [0, 0.05], region: BANK_DEPOSIT_IMAGE_REGION}

; While idling (stable-tracking a tree, waiting for it to deplete, or
; waiting on a bank search) - checked at most once every checkMs, roll
; chance to roam the cursor within IDLE_WANDER_REGION for durationMs.
IDLE_WANDER_REGION_FRAC := 0.95
IDLE_WANDER_REGION := CenteredScreenRegion(IDLE_WANDER_REGION_FRAC)
IDLE_WANDER := {chance: 0.20, checkMs: 2000, durationMs: [750, 5000], region: IDLE_WANDER_REGION}
; ==========================================================================

ChopStep() {
    ok := TrackAndClick({
        target: TREE_TARGET, refX: CHAR_X, refY: CHAR_Y,
        acquireRadii: ACQUIRE_RADII, region: GameZoneRegion(),
        trackRadius: TRACK_RADIUS_PX, maxDriftPx: MAX_DRIFT_PX,
        stableTicks: STABLE_TICKS_REQUIRED, moveTolerancePx: MOVE_TOLERANCE_PX,
        reclickAfterMs: RECLICK_AFTER_MS, ctrl: true,
        clickSettleMs: CLICK_SETTLE_MS,
        acquireDelayChance: ACQUIRE_DELAY_CHANCE, acquireDelayMs: ACQUIRE_DELAY_MS,
        flow: TREE_FLOW,
        wander: IDLE_WANDER,
        until: () => SlotFull(INVENTORY_FULL_SLOT),
        label: "woodcutting-flow-chop"
    })
    if (ok)
        MaybeTakeBreak({chance: BREAK_AFTER_FULL_CHANCE, breakMs: BREAK_AFTER_FULL_MS, label: "woodcutting-flow"})
    return ok
}

BankStep() {
    return DepositAllToBank({
        marker: BANK_MARKER, markerRegion: BANK_MARKER_REGION, markerWaitTimeoutMs: MARKER_WAIT_TIMEOUT_MS,
        markerCtrl: true, depositCtrl: false, depositSearchDelayMs: DEPOSIT_SEARCH_DELAY_MS,
        settleMs: CLICK_SETTLE_MS, depositSettleMs: DEPOSIT_SETTLE_MS,
        depositDistractedChance: DEPOSIT_DISTRACTED_CHANCE, depositDistractedMs: DEPOSIT_DISTRACTED_MS,
        markerFlow: MARKER_FLOW,
        depositFlow: DEPOSIT_FLOW,
        wander: IDLE_WANDER,
        deposit: {path: BANK_DEPOSIT_IMAGE_PATH, w: BANK_DEPOSIT_IMAGE_W, h: BANK_DEPOSIT_IMAGE_H,
            tol: 5, transColor: "0x00FF00"},
        depositRegion: BANK_DEPOSIT_IMAGE_REGION, depositWaitTimeoutMs: DEPOSIT_WAIT_TIMEOUT_MS,
        confirmCondition: () => !SlotFull(CONFIRM_EMPTY_SLOT), confirmTimeoutMs: CONFIRM_TIMEOUT_MS,
        label: "woodcutting-flow-bank"
    })
}

RunWoodcuttingFlow() {
    return StepLoop({
        steps: [
            {name: "chop", run: ChopStep},
            {name: "bank", run: BankStep}
        ],
        retries: STEP_RETRIES, maxCycles: MAX_CYCLES,
        breakChance: BREAK_AFTER_BANK_CHANCE, breakMs: BREAK_AFTER_BANK_MS,
        sessionLengthMs: SESSION_LENGTH_MS,
        label: "woodcutting-flow"
    })
}

InstallBotHarness({
    run: RunWoodcuttingFlow,
    label: "woodcutting-flow"
})
