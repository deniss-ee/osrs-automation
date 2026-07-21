; ============================================================
; v6 Motherlode2 bot - pay-dirt slot verification (gem auto-drop)
;
; Same full loop as Bots\motherlode.ahk (mine -> hopper -> sack/bank ->
; return, forever until F6), but replaces that file's gem-workaround
; logic (dual indicator-slot AND-gate, AnySlotEmpty's full-28-slot
; scan) with a simpler mechanism: a pointer walks inventory slots
; FIRST_CHECK_SLOT(2)->28 in order - slot 1 is permanently skipped,
; since it always holds the hammer (a fixed Motherlode tool), never
; pay-dirt and never empty. Once a slot fills, check it against
; Images\pay-dirt.png - if it matches, the slot is confirmed real
; pay-dirt and the pointer advances; if it doesn't match (a gem),
; shift-click (drop) it and re-check the same slot next tick. Once
; slot 28 is confirmed pay-dirt, the inventory is genuinely full of
; pay-dirt (plus the hammer) - no gems anywhere, by construction, so
; hopper-deposit confirmation collapses back to a single-slot check
; instead of scanning all 28.
;
; NEW FILE, not an edit to motherlode.ahk - the working bot stays
; untouched as a fallback. Everything except the mine-phase fullness
; mechanism (vein tracking, hopper marker, sack/bank/return phases,
; hotkey harness, all their tuned constants) started out copied
; unchanged; the sack phase's slot-fill wait was later reworked into a
; first-wait+retry-forever loop (see WithdrawAndBankOnce()) - everything
; else in that phase is still untouched.
;
; Explicitly NOT addressed here: gems appearing during the sack-
; withdrawal phase (WithdrawAndBankOnce/SACK_SLOTS) - the user's spec
; only covers the mining-phase pointer walk, so gem-handling there is
; still whatever motherlode.ahk did (nothing). Same deferred-scope
; treatment as rockfall clearing.
;
; WHAT IT DOES
;   F5  = start the full mine->hopper->sack->bank->return loop, forever
;   F8  = probe the current pay-dirt check pointer + sack slots
;   F6  = request stop (interrupts instantly, mid-track or mid-wait)
;   Esc = exit the script
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "motherlode2"
TrimLogOnStart()

; ======= EDIT THESE FOR YOUR TEST =======================================
; --- Vein acquire/track (TrackAndClick - same composite as Woodcutting) ---
VEIN_COLORS := [0x00FF00, 0x00B809]   ; candidate vein overlay colors, equal priority

COLOR_TOL      := 5
BLOCK_W        := 27
BLOCK_H        := 27
VERIFY_PERCENT := 100

REF_X := 1248, REF_Y := 707     ; character's on-screen point (acquire proximity) -
                                 ; reuses Woodcutting's calibrated value; recheck if
                                 ; the Motherlode camera/zoom setup differs.
ACQUIRE_RADII := [90, 270]     ; smaller than Woodcutting's [250,600] - veins
                                 ; cluster near the character, no need to search wide.

; Same values as motherlode.ahk's live-tuned settings (2026-07-20/21) -
; see that file's history for the full tuning story (drift-reject was
; hijacking neighboring veins before settling; raised together to keep
; maxDriftPx under half of trackRadius).
TRACK_RADIUS_PX := 90
MAX_DRIFT_PX    := 45

; Pacing - same fastest-proven defaults as Woodcutting. Tune to taste.
STABLE_TICKS_REQUIRED   := 2
MOVE_TOLERANCE_PX       := 5
CLICK_COOLDOWN_MS       := 1500
WALK_RECLICK_TIMEOUT_MS := 3000
CLICK_USE_CTRL          := true

; --- Pay-dirt slot verification (replaces INDICATOR_SLOT/AND-gate) ---
; Slot 1 always holds the hammer - a permanent Motherlode tool, never
; pay-dirt and never empty. The pointer walk and the hopper-empty
; confirm both skip it entirely, starting at slot 2 instead.
HAMMER_SLOT := 1
FIRST_CHECK_SLOT := HAMMER_SLOT + 1

; The pointer that walks inventory slots FIRST_CHECK_SLOT->28 in order -
; see MineFullnessCheck()/DropSlot() below. Resets to FIRST_CHECK_SLOT
; both at the start of a run and after every confirmed hopper deposit.
g_CheckSlot := FIRST_CHECK_SLOT

; Set by DepositHopper() each call: true if that deposit needed the
; retry fallback (past the first patient wait). CONFIRMED LIVE
; (2026-07-21 14:12-14:13 log): the one time this happened, mining
; resumed afterward but stalled hard - the bot clicked the same
; "STABLE" vein 11 times over 22 seconds and never gained a single new
; pay-dirt item past the one slot it had already confirmed. TrackAndClick's
; own progressTimeoutMs didn't catch this because clicks WERE happening
; regularly (that's what resets its clock) - the stall was specifically
; in the pay-dirt pipeline (hopper/sack), invisible to vein-click
; activity. So: a deposit needing retries is treated as a cue to head
; to the sack/bank phase immediately rather than resuming mining that
; may be unable to make real progress. See MineLoop()/DepositHopper().
g_HopperWasFull := false

PAY_DIRT_IMAGE_PATH := A_ScriptDir "\..\Images\pay-dirt.png"
PAY_DIRT_IMAGE_W := 72, PAY_DIRT_IMAGE_H := 64   ; confirmed via direct pixel inspection -
                                                    ; exactly matches INV_SLOT_W/H
PAY_DIRT_IMAGE_TOL := 5
PAY_DIRT_TRANS_COLOR := "0x00FF00"   ; confirmed via direct pixel inspection - same
                                        ; convention as sack.png/deposit-motherlode.png

GEM_DROP_SETTLE_MS := 300   ; settle after shift-clicking a gem away - starting point,
                              ; tune live like every other settle delay this project

; Same dual-timeout pattern as Woodcutting (Lib\Steps.ahk's TrackAndClick):
; PROGRESS_TIMEOUT_MS is the real safety net (resets on any acquire/
; depletion/click), OVERALL_TIMEOUT_MS is just a generous backstop.
; Also the ultimate backstop if the pay-dirt pointer ever got stuck
; (e.g. a shift-click that doesn't register) - no separate per-slot
; retry cap is added on top of this.
PROGRESS_TIMEOUT_MS := 300000
OVERALL_TIMEOUT_MS  := 1800000

; --- Hopper (single whole-screen FindFilledBlock + click, no tracking) ---
HOPPER_COLOR   := 0xC9FFC4
HOPPER_TOL     := 5
HOPPER_BLOCK_W := 27
HOPPER_BLOCK_H := 27
HOPPER_WAIT_TIMEOUT_MS := 15000   ; give up + stop if the hopper marker never appears

; After clicking the hopper, wait for the inventory to clear. Simpler
; than motherlode.ahk's AnySlotEmpty scan - since gems never
; accumulate here, depositing pay-dirt should empty the WHOLE
; inventory at once, so a single-slot check (same shape as
; Woodcutting's Bank()) is enough.
;
; The hopper is a SHARED resource - if it's already backed up with ore
; from a previous run or other players, a single click doesn't always
; register a deposit (2026-07-21 log: "waiting for inventory to clear"
; sat forever after one click, because the ore was still queued, not
; because anything was broken). Fixed with a two-phase wait: the FIRST
; click gets a normal, patient HOPPER_FIRST_WAIT_MS - in the common
; case one click is enough and there's no reason to hammer the hopper
; with re-clicks. Only if that first wait times out does it downgrade
; into re-clicking every HOPPER_RECLICK_MS. HOPPER_EMPTY_WAIT_TIMEOUT_MS
; is the TOTAL retry budget across the first wait + all re-clicks,
; raised to a generous 10 minutes since how long the hopper takes to
; drain is outside our control.
HOPPER_FIRST_WAIT_MS := 15000
HOPPER_RECLICK_MS := 1500
HOPPER_EMPTY_WAIT_TIMEOUT_MS := 600000
HOPPER_CLICK_SETTLE_MS := 600   ; settle after the hopper deposit registers, same
                                  ; reasoning as SACK_CLICK_SETTLE_MS below

HOPPER_CYCLES := 7   ; how many mine->hopper cycles before moving on to the sack/bank phase

POLL_MS := 150   ; tick-aligned poll interval for TrackAndClick + all waits

; --- Entrance to sack platform (whole-screen find+click, one-shot) ---
ENTRANCE_COLOR := 0x5676FF
ENTRANCE_TOL   := 5
ENTRANCE_BLOCK_W := 27
ENTRANCE_BLOCK_H := 27
ENTRANCE_WAIT_TIMEOUT_MS := 15000

; --- Arrival confirmation at the sack platform: wait until a green block's
; CENTER is exactly at (ARRIVE_SACK_X, ARRIVE_SACK_Y) - see BlockAtPoint()
; (Lib\Find.ahk). ARRIVE_SACK_POS_TOL_PX is slack around that expected
; center; tune live from the log like MAX_DRIFT_PX was tuned. ---
ARRIVE_SACK_COLOR := 0x00FF00
ARRIVE_SACK_TOL   := 5
ARRIVE_SACK_BLOCK_W := 27
ARRIVE_SACK_BLOCK_H := 27
ARRIVE_SACK_X := 1583
ARRIVE_SACK_Y := 450
ARRIVE_SACK_POS_TOL_PX := 15
ARRIVE_SACK_WAIT_TIMEOUT_MS := 30000

; --- Sack withdrawal (FindImage, same green-transparency convention as
; deposit-motherlode.png), then wait for slots 2/3/4 to fill - re-clicking
; forever every SACK_SLOTS_RECLICK_MS if the first SACK_SLOTS_FIRST_WAIT_MS
; wait isn't enough (see WithdrawAndBankOnce). Diverges from motherlode.ahk
; here (that file does a single click + single wait); the bank marker,
; deposit, and gem-handling below are still copied verbatim. NOT addressed
; by the pay-dirt pointer walk (that's mine-phase only, per the user's
; spec) - see the header comment. ---
SACK_IMAGE_PATH := A_ScriptDir "\..\Images\sack.png"
SACK_IMAGE_W := 44
SACK_IMAGE_H := 16
SACK_IMAGE_TOL := 5
SACK_TRANS_COLOR := "0x00FF00"
SACK_WAIT_TIMEOUT_MS := 15000
SACK_CLICK_SETTLE_MS := 600    ; the bank marker moves right after taking items from the sack -
                                ; without this, the marker search below can start before it's
                                ; settled and miss the click. Runs right after the FIRST sack
                                ; click each cycle, before that click's slot-fill wait (same
                                ; position as motherlode.ahk) - NOT after the wait, so it overlaps
                                ; the natural fill time instead of adding on top of it: if slots
                                ; take longer than this to fill anyway (the common case, per live
                                ; logs), this pause costs 0 extra wall-clock time. A prior attempt
                                ; to move it to after the wait made every cycle strictly slower for
                                ; no benefit - reverted 2026-07-21. Lowered from motherlode.ahk's
                                ; 1200 to 600 (user's call) since it's pure safety margin, not a
                                ; measured-necessary value.
SACK_SLOTS := [2, 3, 4]

; First wait after each sack click, then re-click+re-wait forever (no cap)
; if that's not enough - same first-wait/reclick shape as
; HOPPER_FIRST_WAIT_MS/HOPPER_RECLICK_MS. No fallback here: confirmed live
; (2026-07-21) the sack always holds exactly SACK_CYCLES(7) runs worth of
; pay-dirt - a delay past the first wait is delivery/registration lag
; (same shared-resource flakiness as DepositHopper()), never an actually-
; empty sack, so retrying forever until slots fill is correct, not risky.
SACK_SLOTS_FIRST_WAIT_MS := 7500
SACK_SLOTS_RECLICK_MS := 1500

; --- Motherlode bank marker (own size/tolerance - different marker from
; Woodcutting's BANK_COLOR/21x21) + deposit-all image (same image/consts
; as Woodcutting's Bank(), duplicated here per this project's
; one-hardcoded-copy-per-bot convention, not shared via Lib) ---
MLBANK_COLOR := 0xFF00FF
MLBANK_TOL   := 5
MLBANK_BLOCK_W := 31
MLBANK_BLOCK_H := 31
MLBANK_CLICK_OFFSET_Y := 32   ; the marker's raw center click was landing off the real
                                ; clickable spot - offset down to compensate
MLBANK_WAIT_TIMEOUT_MS := 15000

DEPOSIT_IMAGE_PATH := A_ScriptDir "\..\Images\deposit-motherlode.png"
DEPOSIT_IMAGE_W := 80
DEPOSIT_IMAGE_H := 72
DEPOSIT_IMAGE_TOL := 5
DEPOSIT_TRANS_COLOR := "0x00FF00"
DEPOSIT_WAIT_TIMEOUT_MS := 15000
DEPOSIT_CONFIRM_TIMEOUT_MS := 5000   ; wait for slots 2/3/4 to empty after clicking deposit

SACK_CYCLES := HOPPER_CYCLES   ; tied to HOPPER_CYCLES - one sack/bank trip per hopper load

; --- Exit the sack platform + confirm arrival back at the mine (same
; CENTER-coordinate convention as ARRIVE_SACK_*) ---
EXIT_COLOR := 0x0000FF
EXIT_TOL   := 5
EXIT_BLOCK_W := 29
EXIT_BLOCK_H := 29
EXIT_WAIT_TIMEOUT_MS := 15000

; Same CENTER semantics as ARRIVE_SACK_* above (see BlockAtPoint()).
ARRIVE_MINE_COLOR := 0xFFFF00
ARRIVE_MINE_TOL   := 5
ARRIVE_MINE_BLOCK_W := 11
ARRIVE_MINE_BLOCK_H := 11
ARRIVE_MINE_X := 864
ARRIVE_MINE_Y := 1307
ARRIVE_MINE_POS_TOL_PX := 25
ARRIVE_MINE_WAIT_TIMEOUT_MS := 30000
; ========================================================================

F5:: RunFullLoop()
F8:: ProbeSlots()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

; Diagnostic: press F8 any time (bot doesn't need to be running) with a
; KNOWN, visually-confirmed inventory state to see exactly what the
; current pay-dirt check pointer AND the sack-withdrawal slots (2/3/4)
; are reading - same tool every other bot uses (SlotProbe, shared via
; Lib\Inv.ahk).
ProbeSlots() {
    Say(SlotProbe(g_CheckSlot) "`n`n" SlotProbe(2) "`n`n" SlotProbe(3) "`n`n" SlotProbe(4))
}

RunFullLoop() {
    global g_StopRequested, g_CheckSlot
    g_StopRequested := false
    g_CheckSlot := FIRST_CHECK_SLOT

    Say("Motherlode2 started: veins=" VeinColorsMsg()
        . " hopperCycles=" HOPPER_CYCLES " sackCycles=" SACK_CYCLES)

    try {
        loop {
            if (!FullCycle()) {
                Say("Full cycle failed - stopping (see log for which step)")
                break
            }
        }
    } catch BotStopped as e {
        Say("STOPPED by F6")
    }
}

; One full lap: mine->hopper (x HOPPER_CYCLES) -> sack platform ->
; withdraw+bank (x SACK_CYCLES) -> back to the mine. Returns false and
; stops the whole bot cleanly the instant any step fails (no partial
; retry) - same fail-clean convention as every wait in this file.
FullCycle() {
    if (!MineLoop())
        return false
    if (!GoToSackArea())
        return false

    loop SACK_CYCLES {
        cycleNum := A_Index
        Say("Sack/bank cycle " cycleNum "/" SACK_CYCLES)
        if (!WithdrawAndBankOnce())
            return false
    }

    if (!ReturnToMine())
        return false

    return true
}

MineLoop() {
    global g_HopperWasFull
    loop HOPPER_CYCLES {
        cycleNum := A_Index
        mineOpts := {
            colors: VEIN_COLORS, tol: COLOR_TOL, blockW: BLOCK_W, blockH: BLOCK_H, verifyPercent: VERIFY_PERCENT,
            refX: REF_X, refY: REF_Y, acquireRadii: ACQUIRE_RADII, trackRadius: TRACK_RADIUS_PX,
            maxDriftPx: MAX_DRIFT_PX, stableTicks: STABLE_TICKS_REQUIRED, moveTolerancePx: MOVE_TOLERANCE_PX,
            cooldownMs: CLICK_COOLDOWN_MS, reclickAfterMs: WALK_RECLICK_TIMEOUT_MS, ctrl: CLICK_USE_CTRL,
            until: MineFullnessCheck, timeoutMs: OVERALL_TIMEOUT_MS,
            progressTimeoutMs: PROGRESS_TIMEOUT_MS, pollMs: POLL_MS
        }

        filled := TrackAndClick(mineOpts)
        if (!filled) {
            Say("Mine loop gave up (no progress or overall timeout) - stopping")
            return false
        }

        Say("Inventory full - depositing into hopper (cycle " cycleNum "/" HOPPER_CYCLES ")")
        if (!DepositHopper()) {
            return false
        }

        ; Confirmed live (2026-07-21): a deposit that needed the retry
        ; fallback was followed by mining stalling hard - the vein kept
        ; getting clicked but no new pay-dirt was gained. Treat that as
        ; a cue to go empty the sack now rather than push through more
        ; (possibly unproductive) mining cycles.
        if (g_HopperWasFull) {
            Say("Hopper needed retries - heading to sack/bank now instead of continuing to mine"
                . " (stopped after cycle " cycleNum "/" HOPPER_CYCLES ")")
            return true
        }
    }

    return true
}

; TrackAndClick's until-condition: walks inventory slots
; FIRST_CHECK_SLOT->28 in order via g_CheckSlot (slot 1/HAMMER_SLOT is
; permanently skipped - it's always the hammer, never pay-dirt, never
; empty). A slot that's still empty just means "keep mining, not done
; yet" (return false). A slot that just filled gets classified against
; pay-dirt.png: a real match advances the pointer; anything else (a
; gem) gets shift-clicked away via DropSlot() and re-checked next tick
; (pointer doesn't move). Returns true only once slot 28 is confirmed
; real pay-dirt - at that point the inventory is genuinely full of
; pay-dirt (plus the hammer in slot 1), no gems anywhere.
MineFullnessCheck() {
    global g_CheckSlot

    if (g_CheckSlot > 28)
        return true

    if (!SlotFull(g_CheckSlot))
        return false

    SlotCorner(g_CheckSlot, &cx, &cy)
    isPayDirt := FindImage(cx, cy, cx + INV_SLOT_W - 1, cy + INV_SLOT_H - 1,
        PAY_DIRT_IMAGE_PATH, PAY_DIRT_IMAGE_W, PAY_DIRT_IMAGE_H, PAY_DIRT_IMAGE_TOL, PAY_DIRT_TRANS_COLOR, &fx, &fy)

    if (isPayDirt) {
        Say("Slot " g_CheckSlot " confirmed pay-dirt")
        g_CheckSlot += 1
        return g_CheckSlot > 28
    }

    Say("Slot " g_CheckSlot " is NOT pay-dirt - dropping it")
    DropSlot(g_CheckSlot)
    return false
}

; Shift-click drop, used by MineFullnessCheck() to get rid of a gem
; that isn't pay-dirt. Settles afterward so the next SlotFull/FindImage
; check isn't racing the drop animation.
DropSlot(slotIndex) {
    SlotCenter(slotIndex, &x, &y)
    ClickAt(x, y, false, true)
    Pause(GEM_DROP_SETTLE_MS)
}

; Whole-screen search for the hopper marker, click it, then wait for
; the inventory to clear. The FIRST click gets a normal, patient
; HOPPER_FIRST_WAIT_MS - in the common case one click is enough. Only
; if that first wait times out does it downgrade into re-clicking
; every HOPPER_RECLICK_MS (the hopper is shared - other players/a
; previous run can leave it backed up with ore still queued to drain,
; so a single click not registering isn't a bug to give up on quickly,
; it just means "keep trying until it's actually your turn"), for up
; to the generous HOPPER_EMPTY_WAIT_TIMEOUT_MS total budget. Stops the
; whole bot cleanly (via BotStopped or a plain false return) if the
; marker itself never appears, or the inventory truly never clears
; within that budget - no infinite silent retry past that point.
DepositHopper() {
    global g_CheckSlot, g_HopperWasFull

    g_HopperWasFull := false
    Say("Hopper: depositing (first wait " HOPPER_FIRST_WAIT_MS "ms, then re-clicking every "
        . HOPPER_RECLICK_MS "ms until clear, up to " HOPPER_EMPTY_WAIT_TIMEOUT_MS "ms total)")

    t0 := A_TickCount
    firstAttempt := true
    loop {
        if (!FindAndClickBlock({
            color: HOPPER_COLOR, tol: HOPPER_TOL, blockW: HOPPER_BLOCK_W, blockH: HOPPER_BLOCK_H,
            ctrl: CLICK_USE_CTRL, waitTimeoutMs: HOPPER_WAIT_TIMEOUT_MS, pollMs: POLL_MS,
            label: "Hopper", itemLabel: "hopper marker"
        }))
            return false

        ; No gems ever accumulate here (MineFullnessCheck drops them
        ; immediately during mining), so a real deposit clears every
        ; slot except the hammer (slot 1/HAMMER_SLOT, always full) -
        ; checking FIRST_CHECK_SLOT (2) is enough, unlike motherlode.ahk's
        ; AnySlotEmpty scan.
        waitMs := firstAttempt ? HOPPER_FIRST_WAIT_MS : HOPPER_RECLICK_MS
        firstAttempt := false
        if (WaitUntil(() => !SlotFull(FIRST_CHECK_SLOT), waitMs, POLL_MS))
            break

        ; Confirmed live (2026-07-21): needing this fallback correlates
        ; with mining stalling afterward - see the flag's declaration
        ; comment above g_HopperWasFull for the full story.
        g_HopperWasFull := true

        elapsed := A_TickCount - t0
        if (elapsed > HOPPER_EMPTY_WAIT_TIMEOUT_MS) {
            Say("Hopper: inventory still not clear after " HOPPER_EMPTY_WAIT_TIMEOUT_MS "ms of retries - stopping")
            return false
        }
        Say("Hopper: not clear yet after " elapsed "ms - re-clicking")
    }

    g_CheckSlot := FIRST_CHECK_SLOT
    Say("Hopper: inventory cleared - settling " HOPPER_CLICK_SETTLE_MS "ms before continuing")
    Pause(HOPPER_CLICK_SETTLE_MS)
    return true
}

; Whole-screen find+click the sack-platform entrance marker, then wait
; for the arrival marker to appear at its exact expected point - same
; fail-clean shape as DepositHopper().
GoToSackArea() {
    if (!FindAndClickBlock({
        color: ENTRANCE_COLOR, tol: ENTRANCE_TOL, blockW: ENTRANCE_BLOCK_W, blockH: ENTRANCE_BLOCK_H,
        ctrl: CLICK_USE_CTRL, waitTimeoutMs: ENTRANCE_WAIT_TIMEOUT_MS, pollMs: POLL_MS,
        label: "GoToSackArea", itemLabel: "entrance marker"
    }))
        return false

    ArrivedAtSack() {
        return BlockAtPoint(ARRIVE_SACK_X, ARRIVE_SACK_Y, ARRIVE_SACK_COLOR, ARRIVE_SACK_TOL,
            ARRIVE_SACK_BLOCK_W, ARRIVE_SACK_BLOCK_H, ARRIVE_SACK_POS_TOL_PX, &fx, &fy)
    }

    Say("GoToSackArea: waiting for arrival at sack platform")
    arrived := WaitUntil(ArrivedAtSack, ARRIVE_SACK_WAIT_TIMEOUT_MS, POLL_MS)
    if (!arrived) {
        wholeScreenFound := FindFilledBlock(0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1,
            ARRIVE_SACK_COLOR, ARRIVE_SACK_TOL, ARRIVE_SACK_BLOCK_W, ARRIVE_SACK_BLOCK_H, &wx, &wy)
        if (wholeScreenFound) {
            Say("GoToSackArea: never arrived within " ARRIVE_SACK_WAIT_TIMEOUT_MS "ms - but marker WAS found"
                . " elsewhere on screen at " wx "," wy " (expected near " ARRIVE_SACK_X "," ARRIVE_SACK_Y ") - stopping")
        } else {
            Say("GoToSackArea: never arrived within " ARRIVE_SACK_WAIT_TIMEOUT_MS
                . "ms - marker not found ANYWHERE on screen, not just near the expected point - stopping")
        }
        return false
    }

    Say("GoToSackArea: arrived at sack platform")
    return true
}

; One withdraw+bank round trip. Sack-click + slot-fill wait mirrors
; DepositHopper()'s shape: a patient first wait, then re-click+re-wait
; forever if that's not enough - see SACK_SLOTS_RECLICK_MS above for why
; there's no cap. Everything from the bank marker onward is unchanged
; from motherlode.ahk.
WithdrawAndBankOnce() {
    Say("Sack: withdrawing (first wait " SACK_SLOTS_FIRST_WAIT_MS "ms, then re-clicking every "
        . SACK_SLOTS_RECLICK_MS "ms until slots " SackSlotsMsg() " fill)")

    firstAttempt := true
    loop {
        if (!FindAndClickImage({
            imagePath: SACK_IMAGE_PATH, imageW: SACK_IMAGE_W, imageH: SACK_IMAGE_H, tol: SACK_IMAGE_TOL,
            transColor: SACK_TRANS_COLOR, ctrl: CLICK_USE_CTRL, waitTimeoutMs: SACK_WAIT_TIMEOUT_MS, pollMs: POLL_MS,
            label: "Sack", itemLabel: "sack"
        }))
            return false

        ; Settling here (before the wait, not after) lets this pause overlap the
        ; natural time slots take to fill instead of adding on top of it - see
        ; SACK_CLICK_SETTLE_MS's comment above. Only on the first click: retries
        ; are already spaced SACK_SLOTS_RECLICK_MS apart per the user's spec, and
        ; only happen after a full SACK_SLOTS_FIRST_WAIT_MS already passed with
        ; no fill, so there's no near-instant case on a retry to guard against.
        if (firstAttempt) {
            Say("Sack: settling " SACK_CLICK_SETTLE_MS "ms before checking slots " SackSlotsMsg())
            Pause(SACK_CLICK_SETTLE_MS)
        }

        waitMs := firstAttempt ? SACK_SLOTS_FIRST_WAIT_MS : SACK_SLOTS_RECLICK_MS
        firstAttempt := false
        if (WaitUntil(() => AllSlotsFull(SACK_SLOTS), waitMs, POLL_MS))
            break

        Say("Sack: slots " SackSlotsMsg() " not filled after " waitMs "ms - re-clicking sack")
    }

    if (!FindAndClickBlock({
        color: MLBANK_COLOR, tol: MLBANK_TOL, blockW: MLBANK_BLOCK_W, blockH: MLBANK_BLOCK_H,
        clickOffsetY: MLBANK_CLICK_OFFSET_Y, ctrl: CLICK_USE_CTRL, waitTimeoutMs: MLBANK_WAIT_TIMEOUT_MS, pollMs: POLL_MS,
        label: "Sack", itemLabel: "deposit-box marker"
    }))
        return false

    if (!FindAndClickImage({
        imagePath: DEPOSIT_IMAGE_PATH, imageW: DEPOSIT_IMAGE_W, imageH: DEPOSIT_IMAGE_H, tol: DEPOSIT_IMAGE_TOL,
        transColor: DEPOSIT_TRANS_COLOR, ctrl: CLICK_USE_CTRL, waitTimeoutMs: DEPOSIT_WAIT_TIMEOUT_MS, pollMs: POLL_MS,
        label: "Sack", itemLabel: "deposit box"
    }))
        return false

    Say("Sack: waiting for slots " SackSlotsMsg() " to empty")
    emptied := WaitUntil(() => AllSlotsEmpty(SACK_SLOTS), DEPOSIT_CONFIRM_TIMEOUT_MS, POLL_MS)
    if (!emptied) {
        Say("Sack: slots " SackSlotsMsg() " still full " DEPOSIT_CONFIRM_TIMEOUT_MS
            . "ms after clicking Deposit All - stopping (deposit may not have registered)")
        return false
    }

    Say("Sack: deposited - slots " SackSlotsMsg() " confirmed empty")
    return true
}

; Whole-screen find+click the exit marker, then wait for the arrival
; marker to appear back at the mine's exact expected point.
ReturnToMine() {
    if (!FindAndClickBlock({
        color: EXIT_COLOR, tol: EXIT_TOL, blockW: EXIT_BLOCK_W, blockH: EXIT_BLOCK_H,
        ctrl: CLICK_USE_CTRL, waitTimeoutMs: EXIT_WAIT_TIMEOUT_MS, pollMs: POLL_MS,
        label: "ReturnToMine", itemLabel: "exit marker"
    }))
        return false

    ArrivedAtMine() {
        return BlockAtPoint(ARRIVE_MINE_X, ARRIVE_MINE_Y, ARRIVE_MINE_COLOR, ARRIVE_MINE_TOL,
            ARRIVE_MINE_BLOCK_W, ARRIVE_MINE_BLOCK_H, ARRIVE_MINE_POS_TOL_PX, &fx, &fy)
    }

    Say("ReturnToMine: waiting for arrival at mine")
    arrived := WaitUntil(ArrivedAtMine, ARRIVE_MINE_WAIT_TIMEOUT_MS, POLL_MS)
    if (!arrived) {
        wholeScreenFound := FindFilledBlock(0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1,
            ARRIVE_MINE_COLOR, ARRIVE_MINE_TOL, ARRIVE_MINE_BLOCK_W, ARRIVE_MINE_BLOCK_H, &wx, &wy)
        if (wholeScreenFound) {
            Say("ReturnToMine: never arrived within " ARRIVE_MINE_WAIT_TIMEOUT_MS "ms - but marker WAS found"
                . " elsewhere on screen at " wx "," wy " (expected near " ARRIVE_MINE_X "," ARRIVE_MINE_Y ") - stopping")
        } else {
            Say("ReturnToMine: never arrived within " ARRIVE_MINE_WAIT_TIMEOUT_MS
                . "ms - marker not found ANYWHERE on screen, not just near the expected point - stopping")
        }
        return false
    }

    Say("ReturnToMine: arrived at mine - mining again")
    return true
}

SackSlotsMsg() {
    msg := ""
    for i, slot in SACK_SLOTS
        msg .= (i = 1 ? "" : "/") slot
    return msg
}

VeinColorsMsg() {
    msg := ""
    for i, c in VEIN_COLORS
        msg .= (i = 1 ? "" : "/") HexColor(c)
    return msg
}

LogLine("Script loaded. F5=start full loop  F8=probe check slot+sack slots  F6=stop  Esc=exit. Veins=" VeinColorsMsg())
ToolTip("motherlode2 ready (pay-dirt verification) - F5 to start", 20, 20)
