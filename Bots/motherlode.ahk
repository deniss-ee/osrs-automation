; ============================================================
; v6 Motherlode bot - PART 1 (mine + hopper skeleton)
;
; Explicitly scoped as a first part: mine veins -> deposit into
; hopper -> repeat HOPPER_CYCLES times -> alarm and stop. NOT included
; yet (later parts): clearing rockfalls, withdrawing the ore sack,
; banking, or walking back to the mine - after the alarm fires, the
; user handles those manually before running this again. That's the
; whole point of the alarm.
;
; Built entirely from already-proven Lib primitives, no new composites:
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
;
; WHAT IT DOES
;   F5  = start the mine/hopper loop
;   F8  = probe both indicator slots (same diagnostic as Woodcutting's F8)
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
TRACK_RADIUS_PX := 70
MAX_DRIFT_PX    := 35

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
    return SlotFull(INDICATOR_SLOT) && SlotFull(SECONDARY_INDICATOR_SLOT)
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

HOPPER_CYCLES := 7   ; how many mine->hopper cycles before alarming + stopping

POLL_MS := 100   ; tick-aligned poll interval for TrackAndClick + both waits

; --- Alarm (after HOPPER_CYCLES cycles complete) ---
ALARM_BEEP_COUNT := 6
ALARM_BEEP_FREQ_HZ := 1200
ALARM_BEEP_MS := 200
ALARM_BEEP_GAP_MS := 150
; ========================================================================

F5:: RunMineLoop()
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
; indicator slots are reading - same tool Woodcutting uses (SlotProbe,
; shared via Lib\Inv.ahk), extended here to both slots of the AND-gate.
ProbeIndicatorSlot() {
    Say(SlotProbe(INDICATOR_SLOT) "`n`n" SlotProbe(SECONDARY_INDICATOR_SLOT))
}

RunMineLoop() {
    global g_StopRequested
    g_StopRequested := false

    Say("Motherlode started: veins=" VeinColorsMsg() " indicatorSlot=" INDICATOR_SLOT
        . " cycles=" HOPPER_CYCLES)

    try {
        MineLoop()
    } catch BotStopped as e {
        Say("STOPPED by F6")
    }
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
            return
        }

        Say("Inventory full - depositing into hopper (cycle " cycleNum "/" HOPPER_CYCLES ")")
        if (!DepositHopper()) {
            return
        }
    }

    Alarm()
}

; Whole-screen search for the hopper marker, click it, then wait for at
; least one inventory slot to empty. Stops the whole bot cleanly (via
; BotStopped or a plain false return) if either step never resolves -
; no infinite silent retry, same pattern as Woodcutting's Bank().
DepositHopper() {
    hopperX := 0, hopperY := 0
    HopperVisible() {
        found := FindFilledBlock(0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1,
            HOPPER_COLOR, HOPPER_TOL, HOPPER_BLOCK_W, HOPPER_BLOCK_H, &fx, &fy)
        if (found) {
            hopperX := fx, hopperY := fy
        }
        return found
    }

    Say("Hopper: waiting for hopper marker")
    found := WaitUntil(HopperVisible, HOPPER_WAIT_TIMEOUT_MS, POLL_MS)
    if (!found) {
        Say("Hopper: hopper marker never appeared within " HOPPER_WAIT_TIMEOUT_MS "ms - stopping")
        return false
    }

    Say("Hopper: clicking hopper at " hopperX "," hopperY)
    ClickAt(hopperX, hopperY, CLICK_USE_CTRL)

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

    Say("Hopper: a slot emptied - back to mining")
    return true
}

; Repeated system beeps to get the user's attention once HOPPER_CYCLES
; cycles are done - the sack/bank/return trip isn't automated yet
; (later part), so this is where the bot hands back control.
Alarm() {
    Say(HOPPER_CYCLES " cycles done - handle sack/bank/return manually")
    loop ALARM_BEEP_COUNT {
        SoundBeep(ALARM_BEEP_FREQ_HZ, ALARM_BEEP_MS)
        Sleep(ALARM_BEEP_GAP_MS)
    }
}

VeinColorsMsg() {
    msg := ""
    for i, c in VEIN_COLORS
        msg .= (i = 1 ? "" : "/") HexColor(c)
    return msg
}

LogLine("Script loaded. F5=start mine/hopper loop  F8=probe indicator slot  F6=stop  Esc=exit. Veins=" VeinColorsMsg())
ToolTip("motherlode part 1 ready - F5 to start", 20, 20)
