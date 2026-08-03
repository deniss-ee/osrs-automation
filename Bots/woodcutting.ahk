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
DEPOSIT_SEARCH_DELAY_MS := [500, 1000]   ; before searching for the deposit button, randomized (1.5x longer per live feedback - felt too fast at [1250,2000])

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

INVENTORY_FULL_SLOT := 28   ; last slot - the only reliable "totally full" signal
CONFIRM_EMPTY_SLOT := 28    ; confirm the deposit via the last slot emptying - slot 1 sits at the
                            ; grid edge next to UI chrome and can false-read as full (confirmed live)

; "roughly every 3 runs" = 1/3 chance, rolled fresh each time
BREAK_AFTER_FULL_CHANCE := 0.75
BREAK_AFTER_FULL_MS := [1000, 10000]     ; after inventory full, before banking
BREAK_AFTER_BANK_CHANCE := 0.5
BREAK_AFTER_BANK_MS := [1000, 5000]      ; after emptying the bank

STEP_RETRIES := 1
MAX_CYCLES := 0   ; bounded first test - raise to 0 for a real unbounded run

; Session length - StepLoop checks this at the cycle seam (after a
; full chop+bank cycle completes, same spot MaybeTakeBreak fires) and
; stops CLEANLY (DONE, not FAILED - see Run.ahk's StepLoop) once
; elapsed, even with MAX_CYCLES=0. Number or [min,max] (rolled once at
; F5) - flat 3h is what was asked for; a range (e.g. [2.75,3.25]*HOUR_MS)
; would avoid a session length that's suspiciously exact every run.
HOUR_MS := 2400000
SESSION_LENGTH_MS := 3 * HOUR_MS

; Mechanical click-settle gaps (glide-arrival -> actual click, and the
; post-click pause TrackAndClick uses to avoid misreading depletion
; flicker). Both are ranges, not flat scalars - ClickAt/TrackAndClick
; resolve them fresh per click via RollMs - a flat unrandomized pause
; reads as mechanical the same way flat jitter would, and was tuned
; too slow at a flat 300ms/300ms in an earlier session.
;
; Trimmed toward zero for a more "on the fly" feel per live feedback -
; HumanGlide's minimum-jerk curve still comes to a full stop at the
; click point either way (that's inherent to the model - zero velocity
; at both ends of every leg, see Act.ahk), so this can't remove the
; stop itself, only the ARTIFICIAL dwell time sitting at it before/
; after the click and before DriftAfterClick's departure leg starts.
; A genuine non-stopping click-through-the-target motion would need a
; new chained-glide primitive in Act.ahk - a real architecture change,
; not a tuning one; this is the cheap version of that ask.
;
; ONE hard constraint: POST_CLICK_SETTLE_MS's low end must stay >= the
; ~100-150ms Steps.ahk documents as the minimum to avoid misreading
; post-click flicker as depletion - CLICK_SETTLE_MS has no equivalent
; floor (verify live that clicks still register reliably this low).
CLICK_SETTLE_MS := [15, 40]
POST_CLICK_SETTLE_MS := [100, 150]

; Deposit-button click, tuned separately from the marker/tree clicks
; above - the marker is a reflexive, always-in-the-same-spot click,
; the deposit button isn't. DEPOSIT_SETTLE_MS is that click's own
; mechanical glide-arrival->click gap (same concept as CLICK_SETTLE_MS
; - short, "on the fly," NOT where the long pause belongs; a real live
; bug this session had this at [500,1000], which put a second-long
; freeze AFTER the mouse arrived at the button - the exact "moved
; there, then waited" symptom the whole distraction feature exists to
; avoid). DEPOSIT_DISTRACTED_CHANCE/_MS is the ONE place the long
; pause belongs: some fraction of the time, once the deposit button is
; CONFIRMED FOUND (not before - "found it, but reacting late" is the
; narrative, not "not looking yet"), wait an extra couple seconds
; before the click-approach starts. DepositAllToBank deliberately does
; NOT enable idle-wander during the deposit button's own search
; (unlike the marker search and the post-deposit confirm wait, which
; both still wander) - a real live bug: wandering during THIS specific
; search could coincidentally leave the cursor sitting on the button
; by the time it was found, making the distraction pause look like the
; opposite of what it's supposed to model. NOT YET LIVE-CONFIRMED.
DEPOSIT_SETTLE_MS := [20, 60]
DEPOSIT_DISTRACTED_CHANCE := 1
DEPOSIT_DISTRACTED_MS := [1000, 4000]

; After EVERY tree click, glide away from the clicked pixel instead of
; leaving the cursor frozen there - distance is 0-25% of screen height
; in a random direction (RandTri-weighted toward the middle of that
; range, see TrackAndClick's own doc comment). NOT YET LIVE-CONFIRMED.
POST_CLICK_DRIFT_CHANCE := .33
POST_CLICK_DRIFT_FRAC := [0, 0.05]

; While idling (stable-tracking a tree, waiting for it to deplete, or
; waiting on a bank search) - checked at most once every checkMs, roll
; chance to roam the cursor within IDLE_WANDER_REGION for durationMs
; (each leg's own distance and pace independently randomized - long
; hops and short ones, fast flicks and slow drifts). Live-confirmed as
; part of this bot (2026-08-01) - a differently-shaped prior version
; of this idea (v7's IdleWander) didn't feel right and was removed;
; this WanderNear-based version replaced it and held up live.
; IDLE_WANDER_REGION_FRAC keeps wandering within the center fraction
; of the screen (CenteredScreenRegion, Find.ahk) - avoids clipping
; near edge UI chrome (chat box, minimap, taskbar).
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
        clickSettleMs: CLICK_SETTLE_MS, postClickSettleMs: POST_CLICK_SETTLE_MS,
        acquireDelayChance: ACQUIRE_DELAY_CHANCE, acquireDelayMs: ACQUIRE_DELAY_MS,
        postClickDriftChance: POST_CLICK_DRIFT_CHANCE, postClickDriftFrac: POST_CLICK_DRIFT_FRAC,
        wander: IDLE_WANDER,
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
        settleMs: CLICK_SETTLE_MS, depositSettleMs: DEPOSIT_SETTLE_MS,
        depositDistractedChance: DEPOSIT_DISTRACTED_CHANCE, depositDistractedMs: DEPOSIT_DISTRACTED_MS,
        wander: IDLE_WANDER,
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
        sessionLengthMs: SESSION_LENGTH_MS,
        label: "woodcutting"
    })
}

InstallBotHarness({
    run: RunWoodcutting,
    label: "woodcutting"
})
