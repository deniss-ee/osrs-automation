; ============================================================
; v7 Bots\woodcutting.ahk
;
; Loop: chop trees (TrackAndClick, two tree-overlay colors) until the
; inventory is full -> click the bank marker (color search, top-right
; quadrant) -> wait for + click the deposit-all image -> confirm empty
; -> repeat. Built entirely from confirmed v7 Lib composites - nothing
; new here (GatherBankLoop, TrackAndClick, DepositAllToBank, SearchZone,
; InstallBotHarness all already live-confirmed in Step 2).
;
; Calibration ported from v6 Bots\woodcutting.ahk's proven values
; (colors/tol/block size/track tuning/timeouts) - REF_X/Y switched to
; the v7 Lib CHAR_X/Y global. Bank marker is NEW config for this v7
; version (color CC5D02, 19x19, top-right quadrant of the game zone,
; via SearchZone) - different from v6's old bank marker, and
; deposit-box.png (80x72) replaces v6's deposit-motherlode.png.
;
; CONTRACT CHANGE from v6: v6's ChopLoop ignored Bank()'s return value
; and just looped back regardless of whether the deposit was ever
; confirmed. This version uses GatherBankLoop, which stops the whole
; bot cleanly the first time bank() fails (matches motherlode2's
; fail-clean FullCycle, not woodcutting's old silent-retry quirk) - if
; you want the old lenient behavior back, ask.
;
; POST_CLICK_SETTLE_MS is new in v7 (standard #16) - v6's blocking Ctrl
; release gave TrackAndClick this cushion for free; tune live if a
; healthy tree gets falsely reported "depleted" after every click.
;
; WHAT IT DOES
;   F5  = start the chop/bank loop
;   F6  = request stop
;   F8  = probe INVENTORY_FULL_SLOT (see it's read as full/empty right now)
;   F12 = exit
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "woodcutting"

; ======= EDIT THESE FOR YOUR SETUP =======================================
; --- Tree acquire/track (TrackAndClick) ---
TREE_COLORS := [0x008B07, 0x56FF50]
COLOR_TOL := 5
BLOCK_W := 51
BLOCK_H := 51
VERIFY_PERCENT := 100

ACQUIRE_RADII := [160, 320]
TRACK_RADIUS_PX := 196
MAX_DRIFT_PX := 98
STABLE_TICKS_REQUIRED := 2
MOVE_TOLERANCE_PX := 4
CLICK_COOLDOWN_MS := 1500
RECLICK_AFTER_MS := 3000
CLICK_USE_CTRL := true
POST_CLICK_SETTLE_MS := 100
GATHER_PRE_DELAY_MS := 0
GATHER_POST_DELAY_MS := 0

INVENTORY_FULL_SLOT := 28

PROGRESS_TIMEOUT_MS := 300000
OVERALL_TIMEOUT_MS := 1800000
POLL_MS := 100

; --- Bank marker search zone (SearchZone, standard #22) - top-right
; quadrant of the game zone. Swap to "full"/"area"/"fixed" here if this
; ever needs narrowing/pinning.
MARKER_ZONE := {mode: "quadrant", quadrant: "top-right"}
; MARKER_ZONE := {mode: "full"}
; MARKER_ZONE := {mode: "area", x: 0, y: 0, w: 0, h: 0, marginPx: 0}
; MARKER_ZONE := {mode: "fixed", x: 0, y: 0, w: 19, h: 19, marginPx: 0}

MARKER_COLORS := [0xCC5D02]
MARKER_TOL := 5
MARKER_BLOCK_W := 19
MARKER_BLOCK_H := 19
MARKER_WAIT_TIMEOUT_MS := 15000

; --- Deposit-all image - path/position/size are the Lib global
; DEPOSIT_BOX_IMAGE_* (Find.ahk) - a genuinely fixed screen button, not
; per-script config (standard #17). Only tol/transColor/timeouts stay here.
DEPOSIT_TOL := 5
DEPOSIT_TRANS_COLOR := "0x00FF00"
DEPOSIT_WAIT_TIMEOUT_MS := 15000
DEPOSIT_CONFIRM_TIMEOUT_MS := 5000
BANK_PRE_DELAY_MS := 0
BANK_POST_DELAY_MS := 0

MAX_CYCLES := 0   ; 0 = forever (real bot); raise for a bounded test run
; ==========================================================================

markerRegion := SearchZone(MARKER_ZONE)
; Fixed position, no margin needed (standard #17 - a truly fixed point never drifts).
depositRegion := SearchZone({mode: "fixed", x: DEPOSIT_BOX_IMAGE_X, y: DEPOSIT_BOX_IMAGE_Y,
    w: DEPOSIT_BOX_IMAGE_W, h: DEPOSIT_BOX_IMAGE_H, marginPx: 0})

GatherTrees() {
    return TrackAndClick({
        colors: TREE_COLORS, tol: COLOR_TOL, blockW: BLOCK_W, blockH: BLOCK_H, verifyPercent: VERIFY_PERCENT,
        refX: CHAR_X, refY: CHAR_Y, acquireRadii: ACQUIRE_RADII, region: GameZoneRegion(),
        trackRadius: TRACK_RADIUS_PX, maxDriftPx: MAX_DRIFT_PX,
        stableTicks: STABLE_TICKS_REQUIRED, moveTolerancePx: MOVE_TOLERANCE_PX,
        cooldownMs: CLICK_COOLDOWN_MS, reclickAfterMs: RECLICK_AFTER_MS, ctrl: CLICK_USE_CTRL,
        postClickSettleMs: POST_CLICK_SETTLE_MS,
        until: () => SlotFull(INVENTORY_FULL_SLOT),
        timeoutMs: OVERALL_TIMEOUT_MS, progressTimeoutMs: PROGRESS_TIMEOUT_MS, pollMs: POLL_MS,
        preDelayMs: GATHER_PRE_DELAY_MS, postDelayMs: GATHER_POST_DELAY_MS
    })
}

BankTrees() {
    return DepositAllToBank({
        markerColors: MARKER_COLORS, markerTol: MARKER_TOL,
        markerBlockW: MARKER_BLOCK_W, markerBlockH: MARKER_BLOCK_H,
        markerRegion: markerRegion, markerWaitTimeoutMs: MARKER_WAIT_TIMEOUT_MS,
        depositImagePath: DEPOSIT_BOX_IMAGE_PATH, depositImageW: DEPOSIT_BOX_IMAGE_W, depositImageH: DEPOSIT_BOX_IMAGE_H,
        depositRegion: depositRegion,
        depositTol: DEPOSIT_TOL, depositTransColor: DEPOSIT_TRANS_COLOR,
        depositWaitTimeoutMs: DEPOSIT_WAIT_TIMEOUT_MS,
        confirmCondition: () => !SlotFull(INVENTORY_FULL_SLOT), confirmTimeoutMs: DEPOSIT_CONFIRM_TIMEOUT_MS,
        ctrl: CLICK_USE_CTRL, pollMs: POLL_MS, label: "Woodcutting",
        preDelayMs: BANK_PRE_DELAY_MS, postDelayMs: BANK_POST_DELAY_MS
    })
}

RunWoodcutting() {
    GatherBankLoop({gather: GatherTrees, bank: BankTrees, maxCycles: MAX_CYCLES, label: "Woodcutting"})
}

ProbeIndicatorSlot() {
    Say(SlotProbe(INVENTORY_FULL_SLOT))
}

InstallBotHarness({
    run: RunWoodcutting,
    label: "Woodcutting",
    probe: ProbeIndicatorSlot
})
