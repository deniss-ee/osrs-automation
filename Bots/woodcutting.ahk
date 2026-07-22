; ============================================================
; v6 Woodcutting bot v1
;
; Loop: find a tree -> chop/track it until depleted, re-acquire the
; next one, until the inventory is full -> find the deposit-box
; marker and click it -> wait for the deposit box's "Deposit All"
; image to appear and click it -> repeat.
;
; Built entirely from already-proven Lib primitives: TrackAndClick
; (Lib\Steps.ahk, unchanged from micro 12) for the chop loop,
; Bank()'s marker/image clicks go through Lib\Steps.ahk's
; FindAndClickBlock/FindAndClickImage (promoted 2026-07-20, once
; Motherlode's own bank/hopper/waypoint clicks made the same one-shot
; find+click shape appear 5x/3x across both bot files).
;
; Pacing defaults to the fastest already-proven-safe values in the
; codebase (Motherlode-tuned) rather than conservative ones - tune the
; constants below to taste.
;
; WHAT IT DOES
;   F5  = start the chop/bank loop
;   F6  = request stop (interrupts instantly, mid-track or mid-wait)
;   F12 = exit the script
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "woodcutting"
TrimLogOnStart()

; ======= EDIT THESE FOR YOUR TEST =======================================
; --- Tree acquire/track (TrackAndClick - same design as micro 12) ---
TREE_COLORS := [0x00FF00, 0x00B809]   ; candidate tree overlay colors, equal priority

COLOR_TOL      := 5
BLOCK_W        := 51
BLOCK_H        := 51
VERIFY_PERCENT := 100

REF_X := 1248, REF_Y := 707     ; character's on-screen point (acquire proximity)
ACQUIRE_RADII := [250, 600]     ; expanding search rings before whole-screen fallback

TRACK_RADIUS_PX := 300   ; narrowed search box half-size once a target is locked
; Raised 40 -> 120 -> 200 (2026-07-20): 120 was still rejecting the SAME
; tree's found position as "a different block" (log showed a stable
; 180px drift every tick while walking toward it, anchor-hold then held
; a stale point forever since the exact old pixel never stopped
; matching the locked color). Raised TRACK_RADIUS_PX alongside it so the
; search net still comfortably covers the wider drift.
MAX_DRIFT_PX    := 200   ; reject a track match this far from the last position

; Pacing - fastest already-proven values (Motherlode-tuned). Tune to taste.
STABLE_TICKS_REQUIRED   := 2
MOVE_TOLERANCE_PX       := 5
CLICK_COOLDOWN_MS       := 1500
WALK_RECLICK_TIMEOUT_MS := 3000
CLICK_USE_CTRL          := true

INDICATOR_SLOT     := 28      ; inventory-full check (Lib\Inv.ahk's SlotFull)

; PROGRESS_TIMEOUT_MS is the real safety net: resets whenever a target is
; acquired, depletes, or gets clicked, so it only fires on genuine
; inactivity, not "this phase is just taking a while." Raised from a flat
; 600000ms total-phase cap (2026-07-20) after that cap killed multiple
; provably-healthy phases (trees were still depleting on a normal ~2min
; cadence right up to the cutoff) - see Lib\Steps.ahk's TrackAndClick doc
; comment for the full story. 300000 (5min) gives ~2x margin over the
; longest observed real depletion gap (~155s) in this codebase's own logs.
PROGRESS_TIMEOUT_MS := 300000
; OVERALL_TIMEOUT_MS is now just a generous absolute backstop underneath
; that, for the pathological case where something keeps generating
; progress signals without ever actually filling the inventory.
OVERALL_TIMEOUT_MS := 1800000

; --- Bank marker (whole-screen FindFilledBlock - same primitive as micro 01/03) ---
BANK_COLOR   := 0xFF00FF
BANK_TOL     := 0
BANK_BLOCK_W := 21
BANK_BLOCK_H := 21
BANK_WAIT_TIMEOUT_MS := 15000   ; give up + stop if the bank marker never appears

; --- Deposit box image (same primitive as micro 06) ---
DEPOSIT_IMAGE_PATH := A_ScriptDir "\..\Images\deposit-motherlode.png"
DEPOSIT_IMAGE_W := 80, DEPOSIT_IMAGE_H := 72   ; must match the PNG's real pixel size
DEPOSIT_IMAGE_TOL := 5
DEPOSIT_TRANS_COLOR := "0x00FF00"
DEPOSIT_WAIT_TIMEOUT_MS := 15000   ; give up + stop if the deposit box never opens
DEPOSIT_CONFIRM_TIMEOUT_MS := 5000   ; give up + stop if depositing doesn't actually empty the inventory

POLL_MS := 100   ; tick-aligned poll interval for both waits below
; ========================================================================

F5:: RunChopLoop()
F8:: ProbeIndicatorSlot()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
; F12 (exit) is defined once in Lib\v6.ahk, shared by every bot.

; Diagnostic: press F8 any time (bot doesn't need to be running) with
; a KNOWN, visually-confirmed inventory state to see exactly what
; SlotFull(INDICATOR_SLOT) is actually reading - use this instead of
; re-guessing SLOT_EMPTY_TOL/SLOT_FULL_OFFSETS blind next time a
; specific item type doesn't get detected as occupied.
ProbeIndicatorSlot() {
    Say(SlotProbe(INDICATOR_SLOT))
}

RunChopLoop() {
    global g_StopRequested
    g_StopRequested := false

    Say("Woodcutting started: trees=" TreeColorsMsg() " indicatorSlot=" INDICATOR_SLOT)

    try {
        ChopLoop()
    } catch BotStopped as e {
        Say("STOPPED by F6")
    }
}

ChopLoop() {
    loop {
        chopOpts := {
            colors: TREE_COLORS, tol: COLOR_TOL, blockW: BLOCK_W, blockH: BLOCK_H, verifyPercent: VERIFY_PERCENT,
            refX: REF_X, refY: REF_Y, acquireRadii: ACQUIRE_RADII, trackRadius: TRACK_RADIUS_PX,
            maxDriftPx: MAX_DRIFT_PX, stableTicks: STABLE_TICKS_REQUIRED, moveTolerancePx: MOVE_TOLERANCE_PX,
            cooldownMs: CLICK_COOLDOWN_MS, reclickAfterMs: WALK_RECLICK_TIMEOUT_MS, ctrl: CLICK_USE_CTRL,
            until: () => SlotFull(INDICATOR_SLOT), timeoutMs: OVERALL_TIMEOUT_MS,
            progressTimeoutMs: PROGRESS_TIMEOUT_MS, pollMs: POLL_MS
        }

        filled := TrackAndClick(chopOpts)
        if (!filled) {
            Say("Chop loop gave up (no progress or overall timeout) - stopping")
            return
        }

        Say("Inventory full - banking")
        Bank()
    }
}

; Bank marker -> deposit-all image -> confirm the inventory emptied, via
; Lib\Steps.ahk's DepositAllToBank (shared with Motherlode2/Crafting). The
; confirm step is what catches a missed/late deposit click that would
; otherwise go unnoticed (the loop bounces back to "inventory full,"
; still full from before, then can't find the bank marker again under the
; still-open deposit UI). ChopLoop deliberately ignores the return, so a
; failed step just loops back and retries rather than stopping the bot.
Bank() {
    DepositAllToBank({
        markerColor: BANK_COLOR, markerTol: BANK_TOL, markerBlockW: BANK_BLOCK_W, markerBlockH: BANK_BLOCK_H,
        markerWaitTimeoutMs: BANK_WAIT_TIMEOUT_MS, markerItemLabel: "deposit-box marker",
        depositImagePath: DEPOSIT_IMAGE_PATH, depositImageW: DEPOSIT_IMAGE_W, depositImageH: DEPOSIT_IMAGE_H,
        depositTol: DEPOSIT_IMAGE_TOL, depositTransColor: DEPOSIT_TRANS_COLOR,
        depositWaitTimeoutMs: DEPOSIT_WAIT_TIMEOUT_MS, depositItemLabel: "deposit box",
        confirmCondition: () => !SlotFull(INDICATOR_SLOT), confirmTimeoutMs: DEPOSIT_CONFIRM_TIMEOUT_MS,
        ctrl: CLICK_USE_CTRL, pollMs: POLL_MS, label: "Bank"
    })
}

TreeColorsMsg() {
    return JoinMsg(TREE_COLORS, "/", HexColor)
}

LogLine("Script loaded. F5=start chop/bank loop  F6=stop  F12=exit. Trees=" TreeColorsMsg())
ToolTip("woodcutting v1 ready - F5 to start", 20, 20)
