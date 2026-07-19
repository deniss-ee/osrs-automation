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
; FindFilledBlock (Lib\Find.ahk, micro 01/03) for the bank marker,
; FindImage (Lib\Find.ahk, micro 06) for the deposit-box image.
;
; Pacing defaults to the fastest already-proven-safe values in the
; codebase (Motherlode-tuned) rather than conservative ones - tune the
; constants below to taste.
;
; WHAT IT DOES
;   F5  = start the chop/bank loop
;   F6  = request stop (interrupts instantly, mid-track or mid-wait)
;   Esc = exit the script
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "woodcutting"

; ======= EDIT THESE FOR YOUR TEST =======================================
; --- Tree acquire/track (TrackAndClick - same design as micro 12) ---
TREE_COLORS := [0x00FF00, 0x00B809]   ; candidate tree overlay colors, equal priority

COLOR_TOL      := 5
BLOCK_W        := 77
BLOCK_H        := 77
VERIFY_PERCENT := 100

REF_X := 1248, REF_Y := 707     ; character's on-screen point (acquire proximity)
ACQUIRE_RADII := [250, 600]     ; expanding search rings before whole-screen fallback

TRACK_RADIUS_PX := 220   ; narrowed search box half-size once a target is locked
; Raised 40 -> 120 (2026-07-20): the log showed the SAME tree's found
; position legitimately moving 50-120px between polls (camera pan while
; walking toward it), which 40px was rejecting as "a different block" -
; that false rejection was cascading into a false "depleted, re-acquire"
; and THAT's what could land on the other candidate color, not a color-
; priority bug. Kept well under half of TRACK_RADIUS_PX so a genuinely
; different nearby same-colored tree still gets rejected.
MAX_DRIFT_PX    := 120   ; reject a track match this far from the last position

; Pacing - fastest already-proven values (Motherlode-tuned). Tune to taste.
STABLE_TICKS_REQUIRED   := 2
MOVE_TOLERANCE_PX       := 5
CLICK_COOLDOWN_MS       := 1500
WALK_RECLICK_TIMEOUT_MS := 3000
CLICK_USE_CTRL          := true

INDICATOR_SLOT     := 28      ; inventory-full check (Lib\Inv.ahk's SlotFull)
OVERALL_TIMEOUT_MS := 600000  ; failsafe - stop if inventory never fills (slow trees take a while)

; --- Bank marker (whole-screen FindFilledBlock - same primitive as micro 01/03) ---
BANK_COLOR   := 0xFF00FF
BANK_TOL     := 0
BANK_BLOCK_W := 24
BANK_BLOCK_H := 24
BANK_WAIT_TIMEOUT_MS := 15000   ; give up + stop if the bank marker never appears

; --- Deposit box image (same primitive as micro 06) ---
DEPOSIT_IMAGE_PATH := A_ScriptDir "\..\..\Images\deposit-motherlode.png"
DEPOSIT_IMAGE_W := 80, DEPOSIT_IMAGE_H := 72   ; must match the PNG's real pixel size
DEPOSIT_IMAGE_TOL := 5
DEPOSIT_TRANS_COLOR := "0x00FF00"
DEPOSIT_WAIT_TIMEOUT_MS := 15000   ; give up + stop if the deposit box never opens

POLL_MS := 100   ; tick-aligned poll interval for both waits below
; ========================================================================

F5:: RunChopLoop()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
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
            until: () => SlotFull(INDICATOR_SLOT), timeoutMs: OVERALL_TIMEOUT_MS, pollMs: POLL_MS
        }

        filled := TrackAndClick(chopOpts)
        if (!filled) {
            Say("Chop loop gave up (overall timeout) - stopping")
            return
        }

        Say("Inventory full - banking")
        Bank()
    }
}

; Whole-screen search for the bank/deposit-box marker, click it, wait
; for the deposit box's "Deposit All" image, click that too. Stops the
; whole bot cleanly (via BotStopped or a plain return) if either step
; never resolves - no infinite silent retry.
Bank() {
    bankX := 0, bankY := 0
    BankMarkerVisible() {
        found := FindFilledBlock(0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1,
            BANK_COLOR, BANK_TOL, BANK_BLOCK_W, BANK_BLOCK_H, &fx, &fy)
        if (found) {
            bankX := fx, bankY := fy
        }
        return found
    }

    Say("Bank: waiting for deposit-box marker")
    found := WaitUntil(BankMarkerVisible, BANK_WAIT_TIMEOUT_MS, POLL_MS)
    if (!found) {
        Say("Bank: deposit-box marker never appeared within " BANK_WAIT_TIMEOUT_MS "ms - stopping")
        return
    }

    Say("Bank: clicking deposit-box marker at " bankX "," bankY)
    ClickAt(bankX, bankY, CLICK_USE_CTRL)

    depositX := 0, depositY := 0
    DepositImageVisible() {
        found := FindImage(0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1,
            DEPOSIT_IMAGE_PATH, DEPOSIT_IMAGE_W, DEPOSIT_IMAGE_H, DEPOSIT_IMAGE_TOL, DEPOSIT_TRANS_COLOR, &fx, &fy)
        if (found) {
            depositX := fx, depositY := fy
        }
        return found
    }

    Say("Bank: waiting for deposit box to open")
    found := WaitUntil(DepositImageVisible, DEPOSIT_WAIT_TIMEOUT_MS, POLL_MS)
    if (!found) {
        Say("Bank: deposit box never opened within " DEPOSIT_WAIT_TIMEOUT_MS "ms - stopping")
        return
    }

    Say("Bank: clicking Deposit All at " depositX "," depositY)
    ClickAt(depositX, depositY, CLICK_USE_CTRL)
    Say("Bank: deposited - back to chopping")
}

TreeColorsMsg() {
    msg := ""
    for i, c in TREE_COLORS
        msg .= (i = 1 ? "" : "/") HexColor(c)
    return msg
}

LogLine("Script loaded. F5=start chop/bank loop  F6=stop  Esc=exit. Trees=" TreeColorsMsg())
ToolTip("woodcutting v1 ready - F5 to start", 20, 20)
