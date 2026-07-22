; ============================================================
; v6 Motherlode bot - PART 1 + PART 2 (full loop)
;
; Full loop, repeated forever until F6: mine veins -> deposit into
; hopper -> repeat HOPPER_CYCLES times -> walk to the sack platform ->
; (withdraw sack -> bank deposit) repeated SACK_CYCLES times -> walk
; back to the mine -> repeat. NOT included: clearing rockfalls - the
; user still handles that manually (it hasn't caused problems in
; practice since rockfalls are rare on this world/route).
;
; Built entirely from Lib primitives (including FindAndClickBlock/
; FindAndClickImage/BlockAtPoint/AllSlotsFull/AllSlotsEmpty, promoted to
; Lib\ on 2026-07-20 once this file's own duplication crossed the
; project's "second real caller" bar - see the sack/bank phase note below):
;   - Mine phase: TrackAndClick (Lib\Steps.ahk, unchanged from
;     Woodcutting/micro 12) - retuned smaller/tighter than Woodcutting
;     because veins are small (27x27) and sit close together, unlike
;     trees spread across open ground. See the tuning comment on
;     TRACK_RADIUS_PX/MAX_DRIFT_PX below and the fuller explanation in
;     Lib\Steps.ahk above TrackAndClick's opts doc.
;   - Hopper phase: a single find+click (FindFilledBlock, Lib\Find.ahk),
;     same pattern as Woodcutting's bank-marker click.
;   - "Wait for deposit to register": AnySlotEmpty() (Lib\Inv.ahk) - ANY
;     of the 28 slots, deliberately not one specific slot, since gems
;     don't drain through the hopper and can sit in any slot indefinitely.
;   - "Inventory full" (the mine phase's until-condition): InventoryFull()
;     requires BOTH INDICATOR_SLOT and SECONDARY_INDICATOR_SLOT full, not
;     just one - matches real Motherlode's own AND-gate. Bug fixed live
;     (2026-07-20): checking only ONE slot let a stray gem (which never
;     drains) make the mine phase think "still full" the instant it
;     returned from depositing, even with 27 other slots genuinely
;     empty - bouncing straight back into another hopper click, rapid-
;     fire, with zero mining in between. See INDICATOR_SLOT's comment
;     below for the full story.
;   - Sack/bank phase (Part 2): GoToSackArea/WithdrawAndBankOnce/
;     ReturnToMine, built on Lib\Steps.ahk's FindAndClickBlock/
;     FindAndClickImage composites (promoted 2026-07-20 once the same
;     one-shot find+click shape appeared 5x/3x across this file and
;     Woodcutting's Bank()). The two "wait until a block is exactly at
;     a fixed x,y" arrival checks (GoToSackArea/ReturnToMine) call
;     Lib\Find.ahk's BlockAtPoint() (also promoted from here). "Wait
;     until every slot in a list is full/empty" (InventoryFull, the
;     sack-slot checks) calls Lib\Inv.ahk's AllSlotsFull/AllSlotsEmpty.
;
; WHAT IT DOES
;   F5  = start the full mine->hopper->sack->bank->return loop, forever
;   F8  = probe indicator + sack slots (same diagnostic as Woodcutting's F8)
;   F6  = request stop (interrupts instantly, mid-track or mid-wait)
;   Esc = exit the script
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "motherlode"
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
ACQUIRE_RADII := [100, 300]     ; smaller than Woodcutting's [250,600] - veins
                                 ; cluster near the character, no need to search wide.

; Both of these start MUCH smaller/tighter than Woodcutting's (220/120) -
; veins are small and sit close together, so the search net (trackRadius)
; must stay small enough to avoid spanning into a NEIGHBORING vein's
; territory, and the drift gate (maxDriftPx) must stay tight since a
; same-colored neighbor could otherwise get hijacked as if it were the
; same vein drifting - see Lib\Steps.ahk's tuning comment above
; TrackAndClick for the full explanation of what these two do
; differently.
; MAX_DRIFT_PX measured live (2026-07-20): 20 was rejecting a confirmed
; SAME vein's re-read at 26px drift as "a different block" - raised to
; 35 for margin. A confirmed genuinely-different neighbor vein was seen
; 57px away, so 35 stays well clear of that while covering the real
; same-vein jitter observed.
; Raised again (2026-07-20): user reported the bot sometimes "jumps
; from one vein to another before settling" - the classic symptom of
; 35 still being tight enough that camera pan right after acquiring
; (before the character finishes walking to the vein) occasionally
; drifts past it, gets rejected as "a different block," concludes the
; original vein depleted, and re-acquires onto whichever vein is now
; closest. Raised to 45 - keeps ~12px of margin under the documented
; 57px neighbor-gap ceiling above while giving real same-vein drift
; more room. TRACK_RADIUS_PX raised alongside it to 100 so maxDriftPx
; stays under half of trackRadius, per Lib\Steps.ahk's tuning guidance.
; If jumping still happens, check the log for "found ... but Npx from
; last position ... rejecting" lines - that N is the real number to
; tune from next, not another guess.
TRACK_RADIUS_PX := 100
MAX_DRIFT_PX    := 45

; Pacing - same fastest-proven defaults as Woodcutting. Tune to taste.
STABLE_TICKS_REQUIRED   := 2
MOVE_TOLERANCE_PX       := 5
CLICK_COOLDOWN_MS       := 1500
WALK_RECLICK_TIMEOUT_MS := 3000
CLICK_USE_CTRL          := true

; "Inventory full" requires BOTH slots full, not just INDICATOR_SLOT
; alone - matches real Motherlode's own indicatorSlot/secondaryIndicatorSlot
; AND-gate. Bug fixed live (2026-07-20): a single gem can land in slot
; 28 without the hopper ever collecting it (gems don't drain through
; the hopper). With only ONE slot checked, that stray gem made the
; mine phase's until-condition fire true the INSTANT it returned to
; mining (before attempting anything) even though the other 27 slots
; had genuine room after depositing - bouncing the bot straight back
; into another hopper click, rapid-fire, with zero mining in between.
; Requiring a SECOND slot to also be full means a lone gem can't fool
; this check by itself - there has to be real, broad fullness.
INDICATOR_SLOT := 28
SECONDARY_INDICATOR_SLOT := 26
InventoryFull() {
    return AllSlotsFull([INDICATOR_SLOT, SECONDARY_INDICATOR_SLOT])
}

; Same dual-timeout pattern as Woodcutting (Lib\Steps.ahk's TrackAndClick):
; PROGRESS_TIMEOUT_MS is the real safety net (resets on any acquire/
; depletion/click), OVERALL_TIMEOUT_MS is just a generous backstop.
PROGRESS_TIMEOUT_MS := 300000
OVERALL_TIMEOUT_MS  := 1800000

; --- Hopper (single whole-screen FindFilledBlock + click, no tracking) ---
HOPPER_COLOR   := 0xC9FFC4
HOPPER_TOL     := 5
HOPPER_BLOCK_W := 27
HOPPER_BLOCK_H := 27
HOPPER_WAIT_TIMEOUT_MS := 15000   ; give up + stop if the hopper marker never appears

; After clicking the hopper, wait for ANY slot to empty (AnySlotEmpty,
; Lib\Inv.ahk - see DepositHopper()) before considering this cycle done.
HOPPER_EMPTY_WAIT_TIMEOUT_MS := 15000
HOPPER_CLICK_SETTLE_MS := 600   ; settle after the hopper deposit registers, same
                                  ; reasoning as SACK_CLICK_SETTLE_MS below

HOPPER_CYCLES := 1   ; how many mine->hopper cycles before moving on to the sack/bank phase

POLL_MS := 150   ; tick-aligned poll interval for TrackAndClick + all waits

; --- Entrance to sack platform (whole-screen find+click, one-shot) ---
ENTRANCE_COLOR := 0x5676FF
ENTRANCE_TOL   := 5
ENTRANCE_BLOCK_W := 27
ENTRANCE_BLOCK_H := 27
ENTRANCE_WAIT_TIMEOUT_MS := 15000

; --- Arrival confirmation at the sack platform: wait until a green block's
; CENTER is exactly at (ARRIVE_SACK_X, ARRIVE_SACK_Y) - see BlockAtPoint()
; below. ARRIVE_SACK_POS_TOL_PX is slack around that expected center;
; tune live from the log like MAX_DRIFT_PX was tuned above. ---
ARRIVE_SACK_COLOR := 0x00FF00
ARRIVE_SACK_TOL   := 5
ARRIVE_SACK_BLOCK_W := 27
ARRIVE_SACK_BLOCK_H := 27
ARRIVE_SACK_X := 1583
ARRIVE_SACK_Y := 450
ARRIVE_SACK_POS_TOL_PX := 15
ARRIVE_SACK_WAIT_TIMEOUT_MS := 30000   ; raised 15000->30000 (2026-07-20): a walk can
                                        ; plausibly take longer than 15s; cheap to allow
                                        ; more time regardless of root cause

; --- Sack withdrawal (FindImage, same green-transparency convention as
; deposit-motherlode.png) + wait for slots 2/3/4 to fill ---
SACK_IMAGE_PATH := A_ScriptDir "\..\Images\sack.png"
SACK_IMAGE_W := 44
SACK_IMAGE_H := 16
SACK_IMAGE_TOL := 5
SACK_TRANS_COLOR := "0x00FF00"
SACK_WAIT_TIMEOUT_MS := 15000
SACK_CLICK_SETTLE_MS := 1200   ; the bank marker moves right after taking items from the sack -
                                ; without this, the marker search below can start before it's
                                ; settled and miss the click. Tick-aligned (600ms = 1 game tick).
SACK_SLOTS := [2, 3, 4]
SACK_SLOTS_WAIT_TIMEOUT_MS := 15000

; --- Motherlode bank marker (own size/tolerance - different marker from
; Woodcutting's BANK_COLOR/21x21) + deposit-all image (same image/consts
; as Woodcutting's Bank(), duplicated here per this project's
; one-hardcoded-copy-per-bot convention, not shared via Lib) ---
MLBANK_COLOR := 0xFF00FF
MLBANK_TOL   := 5
MLBANK_BLOCK_W := 31
MLBANK_BLOCK_H := 31
MLBANK_CLICK_OFFSET_Y := 26   ; the marker's raw center click was landing off the real
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
; Measured live (2026-07-20 21:43 log): FindFilledBlock steadily matched
; this marker's CENTER at 846,1306 - an 18px x-gap from ARRIVE_MINE_X,
; which the previous 15px tolerance rejected every single poll despite
; the marker being found correctly every time. Raised to comfortably
; clear that measured gap.
ARRIVE_MINE_POS_TOL_PX := 25
ARRIVE_MINE_WAIT_TIMEOUT_MS := 10000   ; raised 15000->30000 (2026-07-20): the 2026-07-20
                                        ; 21:15 log showed 15s of 100% "not found" (zero
                                        ; matches anywhere, not just a position miss) after
                                        ; clicking the exit marker - real cause unconfirmed
                                        ; (walk just takes longer? click didn't register?
                                        ; landed elsewhere?), so this is a cheap hedge, not
                                        ; a confirmed fix. See the whole-screen diagnostic
                                        ; fallback in ReturnToMine() for what to check next
                                        ; time this happens.
; ========================================================================

F5:: RunFullLoop()
F8:: ProbeIndicatorSlot()
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
; KNOWN, visually-confirmed inventory state to see exactly what both
; indicator slots AND the three sack-withdrawal slots (2/3/4) are
; reading - same tool Woodcutting uses (SlotProbe, shared via
; Lib\Inv.ahk), extended here for live-tuning the Part 2 sack check.
ProbeIndicatorSlot() {
    Say(SlotProbe(INDICATOR_SLOT) "`n`n" SlotProbe(SECONDARY_INDICATOR_SLOT)
        . "`n`n" SlotProbe(2) "`n`n" SlotProbe(3) "`n`n" SlotProbe(4))
}

RunFullLoop() {
    global g_StopRequested
    g_StopRequested := false

    Say("Motherlode started: veins=" VeinColorsMsg() " indicatorSlot=" INDICATOR_SLOT
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
    loop HOPPER_CYCLES {
        cycleNum := A_Index
        mineOpts := {
            colors: VEIN_COLORS, tol: COLOR_TOL, blockW: BLOCK_W, blockH: BLOCK_H, verifyPercent: VERIFY_PERCENT,
            refX: REF_X, refY: REF_Y, acquireRadii: ACQUIRE_RADII, trackRadius: TRACK_RADIUS_PX,
            maxDriftPx: MAX_DRIFT_PX, stableTicks: STABLE_TICKS_REQUIRED, moveTolerancePx: MOVE_TOLERANCE_PX,
            cooldownMs: CLICK_COOLDOWN_MS, reclickAfterMs: WALK_RECLICK_TIMEOUT_MS, ctrl: CLICK_USE_CTRL,
            until: InventoryFull, timeoutMs: OVERALL_TIMEOUT_MS,
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
    }

    return true
}

; Whole-screen search for the hopper marker, click it, then wait for at
; least one inventory slot to empty. Stops the whole bot cleanly (via
; BotStopped or a plain false return) if either step never resolves -
; no infinite silent retry, same pattern as Woodcutting's Bank().
DepositHopper() {
    if (!FindAndClickBlock({
        color: HOPPER_COLOR, tol: HOPPER_TOL, blockW: HOPPER_BLOCK_W, blockH: HOPPER_BLOCK_H,
        ctrl: CLICK_USE_CTRL, waitTimeoutMs: HOPPER_WAIT_TIMEOUT_MS, pollMs: POLL_MS,
        label: "Hopper", itemLabel: "hopper marker"
    }))
        return false

    ; Wait for ANY slot to empty, not a specific one - gems don't go
    ; through the hopper, so they can sit in any slot (including the
    ; indicator slot) indefinitely; requiring one particular slot to
    ; clear could hang forever on a stray gem. See MineLoop's
    ; until-condition below for the actual fix to the rapid-reclicking
    ; bug this used to cause.
    Say("Hopper: waiting for a slot to empty")
    emptied := WaitUntil(AnySlotEmpty, HOPPER_EMPTY_WAIT_TIMEOUT_MS, POLL_MS)
    if (!emptied) {
        Say("Hopper: no slot emptied within " HOPPER_EMPTY_WAIT_TIMEOUT_MS "ms - stopping")
        return false
    }

    Say("Hopper: a slot emptied - settling " HOPPER_CLICK_SETTLE_MS "ms before continuing")
    Pause(HOPPER_CLICK_SETTLE_MS)
    return true
}

; BlockAtPoint() was promoted verbatim to Lib\Find.ahk (2026-07-20) once
; a second "wait until an exact fixed point" use case existed (see
; ReturnToMine below) - it's generic waypoint-arrival detection, not
; Motherlode-specific logic.

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
        ; Diagnostic fallback (2026-07-20): the position-constrained
        ; search only looks within a small margin around the expected
        ; point (see BlockAtPoint's MARGIN_PX in Lib\Find.ahk), so total
        ; silence there doesn't tell us whether the marker is just
        ; outside that window or genuinely never appeared anywhere. One
        ; whole-screen search on timeout answers that for next time,
        ; instead of guessing blind.
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

; One withdraw+bank round trip: click the sack, wait for slots 2/3/4 to
; fill, click the Motherlode deposit-box marker, wait for the deposit-all
; image, click it, then confirm slots 2/3/4 actually emptied before
; letting the caller loop back to the sack again.
WithdrawAndBankOnce() {
    if (!FindAndClickImage({
        imagePath: SACK_IMAGE_PATH, imageW: SACK_IMAGE_W, imageH: SACK_IMAGE_H, tol: SACK_IMAGE_TOL,
        transColor: SACK_TRANS_COLOR, ctrl: CLICK_USE_CTRL, waitTimeoutMs: SACK_WAIT_TIMEOUT_MS, pollMs: POLL_MS,
        label: "Sack", itemLabel: "sack"
    }))
        return false

    Say("Sack: settling " SACK_CLICK_SETTLE_MS "ms before searching for the bank marker")
    Pause(SACK_CLICK_SETTLE_MS)

    ; Items sometimes stack/combine in the sack, so a withdrawal can
    ; legitimately yield nothing new (the sack's remaining supply ran
    ; out or merged into slots that were already full before this
    ; click) - this can happen on ANY cycle, not just the last one.
    ; NOT a failure: proceed to the bank/deposit steps anyway instead
    ; of stopping the whole bot. If slots 2/3/4 truly are empty going
    ; into the deposit click, the later "confirm emptied" wait below
    ; just passes immediately (they're already empty) - no special
    ; casing needed there.
    Say("Sack: waiting for slots " SackSlotsMsg() " to fill")
    filled := WaitUntil(() => AllSlotsFull(SACK_SLOTS), SACK_SLOTS_WAIT_TIMEOUT_MS, POLL_MS)
    if (!filled) {
        Say("Sack: slots " SackSlotsMsg() " never filled within " SACK_SLOTS_WAIT_TIMEOUT_MS
            . "ms - probably nothing left to withdraw (stacked/combined) - continuing to bank anyway")
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
        ; Diagnostic fallback - see the matching comment in GoToSackArea.
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

LogLine("Script loaded. F5=start full loop  F8=probe indicator+sack slots  F6=stop  Esc=exit. Veins=" VeinColorsMsg())
ToolTip("motherlode ready (mine+hopper+sack+bank+return) - F5 to start", 20, 20)
