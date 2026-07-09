; ============================================================
; motherlode.ahk
; v4 entry point + the "mine" phase for the Motherlode Mine bot,
; combined into one file. MinePhase used to live in its own
; MinePhase.ahk - merged here since the split between "entry
; point" and "the one phase it runs" added a file-hop for no
; real benefit with a single bot/single phase. Shared framework
; classes (Core/Timing/Detection/Actions/Interfaces/Config/
; Diagnostics) stay as separate reusable files - only the two
; Motherlode-specific files collapsed.
;
; Isolation: reads/writes only v4's own config/ and logs/ folders
; (v4/config/auto-motherlode-v2.ini, v4/logs/...) - never the
; legacy repo-root config/ or logs/ folders.
;
; Remaining phases (withdrawSack, depositBank, returnMine1/2)
; are still to be ported. clearRed/clearYellow are now built.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

; Without these, AHK v2 defaults Click/MouseMove/PixelSearch coordinates to
; "Client" (relative to whatever window currently has focus), not "Screen" -
; but every coordinate in v4 (search regions, found vein positions, click
; offsets) is computed as absolute screen pixels. Matches legacy's exact
; CoordMode setup.
CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

#Include ..\..\Core\Engine.ahk
#Include ..\..\Core\EngineContext.ahk
#Include ..\..\Core\FailSafe.ahk
#Include ..\..\Core\Phase.ahk
#Include ..\..\Timing\Waiter.ahk
#Include ..\..\Detection\ColorSearch.ahk
#Include ..\..\Detection\TargetLock.ahk
#Include ..\..\Detection\Telemetry.ahk
#Include ..\..\Detection\StaticAnchor.ahk
#Include ..\..\Interfaces\Inventory.ahk
#Include ..\..\Actions\Humanizer.ahk
#Include ..\..\Actions\Click.ahk
#Include ..\..\Config\Config.ahk
#Include ..\..\Diagnostics\Logger.ahk
#Include ..\..\Diagnostics\WindowFocus.ahk
#Include ..\..\Diagnostics\Overlay.ahk

; ============================================================
; MinePhase - direct port of auto-motherlode-v2.ahk's MinePhase
; (lines 128-238). Two distinct modes, exactly like legacy - this
; is NOT forced into the generic acquire/wait/act/verify shape
; because legacy's real branching (acquisition vs. tracking are
; materially different algorithms) would be distorted by that;
; instead every raw Sleep/Click/PixelGetColor/.ini read legacy
; had is routed through the same four contracts (Detection/
; Timing/Actions/Telemetry) the ruleset requires, just composed
; in the shape the actual behavior needs.
;
; Mode 1 - ACQUIRE (no target locked yet, ctx state "mineHasTarget" = false):
;   Search the full region for BOTH the light and dark vein overlay
;   colors. If both exist, pick whichever is closer to the character's
;   reference point (squared distance, matching legacy exactly).
;
; Mode 2 - TRACK (target locked, ctx state "mineHasTarget" = true):
;   Re-search a narrowed 100x100 box around the last known position,
;   locked onto the SAME color only (never re-considers the other
;   color once locked, matching legacy exactly). Stability gates
;   which click-cadence branch runs; a lost target resets to Mode 1.
; ============================================================
class MinePhase extends Phase {
    ; region: {x1,y1,x2,y2} full vein search area.
    ; veinColors: [light, dark] - overlay color candidates.
    ; referencePoint: {x,y} - character center, used to pick between two
    ; simultaneously-visible veins (legacy: ctx["returnWalkPoint"]).
    ; reqW/reqH: minimum solid block size to count as a vein.
    ; trackBoxRadiusPx: half-width of the narrowed tracking box around the
    ; last known position once locked (legacy: 50, i.e. a 100x100 box).
    ; clickOffsetX/Y: pixel offset applied to every click point AFTER the
    ; block's center is found - e.g. the found block's center is a fixed
    ; distance from the actual clickable ore rock in-game, so this shifts
    ; the click to land on it instead. Configurable via .ini (veinClickOffsetX/Y).
    ; scanBottomUp: when true, searches scan from the bottom of the region
    ; upward instead of top-down, so the first-found pixel (and therefore
    ; the computed block center) is near the bottom-left of the vein
    ; overlay instead of the top-left.
    ; walkReclickTimeoutMs: while walking to a vein (not yet "stable"), if
    ; this much time passes since the last click with still no stability,
    ; click again anyway - prevents getting permanently stuck after exactly
    ; one click if the found position never settles within 2px for 2
    ; consecutive ticks (e.g. due to jitter between search passes).
    ; nextCyclePhases: [ClearRedPhase, ClearYellowPhase] instances, so this
    ; phase can reset their per-cycle state (TargetLock + scratch coords)
    ; at the one transition point where a fresh inventory-full cycle begins -
    ; see ClearRedPhase.ResetForNewCycle.
    __New(region, veinColors, referencePoint, tolerance, reqW, reqH, trackBoxRadiusPx, stableTicksRequired, runMode := false, clickOffsetX := 0, clickOffsetY := 0, scanBottomUp := false, walkReclickTimeoutMs := 3000, nextCyclePhases := "") {
        super.__New("mine")
        this._region := region
        this._veinColors := veinColors
        this._referencePoint := referencePoint
        this._tolerance := tolerance
        this._reqW := reqW
        this._reqH := reqH
        this._trackBoxRadiusPx := trackBoxRadiusPx
        this._lock := TargetLock(stableTicksRequired, 2)
        this._runMode := runMode   ; legacy's ctx["runMode"] - holds Ctrl (force-run) while clicking
        this._clickOffsetX := clickOffsetX
        this._clickOffsetY := clickOffsetY
        this._scanBottomUp := scanBottomUp
        this._walkReclickTimeoutMs := walkReclickTimeoutMs
        this._nextCyclePhases := nextCyclePhases != "" ? nextCyclePhases : []
    }

    ; Click helper matching legacy's HumanClick(x, y, 0, 0, ctx["runMode"])
    ; exactly - Ctrl is only held while this._runMode is truthy. Applies the
    ; configured click offset to the found block center before clicking, and
    ; returns the actual post-offset coordinates via out-params so callers
    ; can log what was REALLY clicked (not the raw found vein position,
    ; which is misleading once an offset is configured).
    ;
    ; Settle delay: legacy's HumanClick does MouseMove -> Sleep(~150ms
    ; jittered) -> Click - giving the game client a moment to register the
    ; cursor actually being over the target (hover/highlight state) before
    ; the click fires. Routed through ctx.waiter/ctx.timing exactly like
    ; every other timed step, keyed on "clickSettle" (see .ini).
    _Click(ctx, x, y, &clickX, &clickY) {
        clickX := x + this._clickOffsetX
        clickY := y + this._clickOffsetY

        if (this._runMode)
            Send("{Ctrl down}")

        ctx.clicker.MoveTo(clickX, clickY, 0, 0, &targetX, &targetY)
        ctx.waiter.After(ctx.timing, "clickSettle")
        ctx.clicker.Press()

        if (this._runMode) {
            ctx.waiter.After(ctx.timing, "ctrlHoldSettle")
            Send("{Ctrl up}")
        }
    }

    Run(ctx) {
        ; Window-focus gate, matching legacy's RequireOsrsWindowActive check
        ; at the top of every phase - without this, the bot would keep
        ; searching/clicking with screen-absolute coordinates even if RuneLite
        ; loses focus (alt-tab, a notification, a second monitor).
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "mine"

        ; Inventory-full gate gets checked first every tick, matching
        ; legacy's exact ordering (before any vein search happens at all).
        if (ctx.inventory.IsFull()) {
            ctx.Log("MinePhase: Inventory full, transitioning to clearRed")
            ; Fresh state for the upcoming clearRed/clearYellow cycle - without
            ; this, a second full-inventory cycle in the same script run (no
            ; process restart) would resume clearRed/clearYellow's _Track mode
            ; using stale target coordinates and a stale TargetLock stability
            ; streak left over from the previous cycle, instead of starting a
            ; clean whole-screen _Acquire search (matches legacy's
            ; ResetBotState(), called at the same transition point).
            ctx.Set("redHasTarget", false)
            ctx.Set("redTargetX", 0)
            ctx.Set("redTargetY", 0)
            ctx.Set("redLastClickTime", 0)
            ctx.Set("yellowTargetX", 0)
            ctx.Set("yellowTargetY", 0)
            ctx.Set("yellowLastClickTime", 0)
            ctx.Set("sackLastClickTime", 0)
            ctx.Set("sackWaitStartedAt", 0)
            ctx.Set("bankPreDelayApplied", false)
            for phase in this._nextCyclePhases
                phase.ResetForNewCycle()
            return "clearRed"
        }

        if (!ctx.Get("mineHasTarget", false))
            return this._Acquire(ctx)
        return this._Track(ctx)
    }

    ; Mode 1: search the full region for both candidate colors, pick
    ; whichever is closer to the reference point if both are present.
    _Acquire(ctx) {
        foundLight := ColorSearch.FindFilledBlock(
            this._region["x1"], this._region["y1"], this._region["x2"], this._region["y2"],
            this._veinColors[1], this._tolerance, this._reqW, this._reqH, &lx, &ly, this._scanBottomUp)
        foundDark := ColorSearch.FindFilledBlock(
            this._region["x1"], this._region["y1"], this._region["x2"], this._region["y2"],
            this._veinColors[2], this._tolerance, this._reqW, this._reqH, &dx, &dy, this._scanBottomUp)

        found := false
        if (foundLight && foundDark) {
            lDist := (lx - this._referencePoint["x"])**2 + (ly - this._referencePoint["y"])**2
            dDist := (dx - this._referencePoint["x"])**2 + (dy - this._referencePoint["y"])**2
            if (lDist <= dDist)
                vx := lx, vy := ly, vColor := this._veinColors[1]
            else
                vx := dx, vy := dy, vColor := this._veinColors[2]
            found := true
        } else if (foundLight) {
            vx := lx, vy := ly, vColor := this._veinColors[1]
            found := true
        } else if (foundDark) {
            vx := dx, vy := dy, vColor := this._veinColors[2]
            found := true
        }

        if (!found)
            return "mine"   ; still searching, no vein visible yet

        ctx.Set("mineHasTarget", true)
        ctx.Set("mineTargetColor", vColor)
        ctx.Set("mineTargetX", vx)
        ctx.Set("mineTargetY", vy)
        ctx.Set("mineLastClickTime", 0)
        this._lock.Reset()
        ctx.Log("MinePhase: Found new vein at [" vx ", " vy "]")

        ; Deliberately do NOT click on this same tick. The vein's color
        ; overlay may not be fully rendered/settled yet at the exact instant
        ; it's first detected (e.g. a fade-in), so a click computed from
        ; this very first detection can land on the overlay's edge/glow
        ; instead of the actual clickable rock - registering in-game as a
        ; plain tile click (yellow) rather than a vein interaction. Just
        ; record the position here; _Track's next-tick "not yet stable,
        ; lastClickTime == 0" branch fires the actual first click using a
        ; freshly re-verified position one tick later.
        ctx.failsafe.ResetPhaseTimer(ctx)
        return "mine"
    }

    ; Mode 2: re-search a narrowed box around the last known position,
    ; locked onto the same color only. Position always updates to the
    ; latest real coordinates (TargetLock never freezes it); stability
    ; only gates which click-cadence branch runs.
    _Track(ctx) {
        lastX := ctx.Get("mineTargetX", 0)
        lastY := ctx.Get("mineTargetY", 0)
        lockedColor := ctx.Get("mineTargetColor")

        rx1 := Max(this._region["x1"], lastX - this._trackBoxRadiusPx)
        ry1 := Max(this._region["y1"], lastY - this._trackBoxRadiusPx)
        rx2 := Min(this._region["x2"], lastX + this._trackBoxRadiusPx)
        ry2 := Min(this._region["y2"], lastY + this._trackBoxRadiusPx)

        nvx := 0, nvy := 0
        found := ColorSearch.FindFilledBlock(rx1, ry1, rx2, ry2, lockedColor, this._tolerance, this._reqW, this._reqH, &nvx, &nvy, this._scanBottomUp)
        this._lock.Observe(found, nvx, nvy, &outX, &outY)

        if (!found) {
            ctx.Log("MinePhase: Lost track of vein or depleted. Finding new vein.")
            ctx.Set("mineHasTarget", false)
            ctx.Set("mineTargetX", 0)
            ctx.Set("mineTargetY", 0)
            return "mine"
        }

        ctx.Set("mineTargetX", outX)
        ctx.Set("mineTargetY", outY)

        if (this._lock.IsStable()) {
            ; Non-blocking cooldown check - matches legacy exactly
            ; (A_TickCount - lastClickTime > cooldown), never a Sleep. The
            ; cooldown duration itself still comes from ctx.timing (the
            ; single source of truth for the value), just compared inline
            ; rather than slept through.
            lastClick := ctx.Get("mineLastClickTime", 0)
            if ((A_TickCount - lastClick) > ctx.timing.BaseMs("mineClickCooldown")) {
                this._Click(ctx, outX, outY, &clickX, &clickY)
                ctx.Set("mineLastClickTime", A_TickCount)
                ctx.Log("MinePhase: Clicked stable vein at [" clickX ", " clickY "] (vein at [" outX ", " outY "])")
                ctx.failsafe.ResetPhaseTimer(ctx)
            }
        } else {
            ; Not yet stable. Click once immediately upon finding the vein,
            ; then re-click if stability still hasn't been reached after
            ; walkReclickTimeoutMs - without this, a vein whose found
            ; position keeps jittering (never landing within 2px for 2
            ; consecutive ticks) would get exactly one click and then never
            ; be clicked again, since IsStable() never becomes true.
            lastClick := ctx.Get("mineLastClickTime", 0)
            if (lastClick = 0 || (A_TickCount - lastClick) > this._walkReclickTimeoutMs) {
                this._Click(ctx, outX, outY, &clickX, &clickY)
                ctx.Set("mineLastClickTime", A_TickCount)
                ctx.Log("MinePhase: Initial click to walk to vein at [" clickX ", " clickY "] (vein at [" outX ", " outY "])")
                ctx.failsafe.ResetPhaseTimer(ctx)
            }
        }

        return "mine"
    }
}

; ============================================================
; ClearRedPhase - direct port of auto-motherlode-v2.ahk's
; ClearRedPhase (lines 240-315). Clears rockfall obstacles that
; block the hopper walkway after the inventory fills up. Same
; acquire/track shape as MinePhase, but searches the WHOLE
; screen (a rockfall can appear anywhere) instead of a fixed
; region, single color instead of two candidates, and no click
; offset - so this is its own small class rather than a
; generalization of MinePhase.
;
; Exit condition: a full-screen search comes back completely
; empty (no target currently locked) -> no more rockfalls ->
; transition to clearYellow.
; ============================================================
class ClearRedPhase extends Phase {
    __New(color, tolerance, reqW, reqH, trackBoxRadiusPx, stableTicksRequired, clearCooldownMs, runMode := false) {
        super.__New("clearRed")
        this._color := color
        this._tolerance := tolerance
        this._reqW := reqW
        this._reqH := reqH
        this._trackBoxRadiusPx := trackBoxRadiusPx
        this._clearCooldownMs := clearCooldownMs
        this._lock := TargetLock(stableTicksRequired, 2)
        this._runMode := runMode
    }

    ; Called by MinePhase on the mine->clearRed transition so a fresh
    ; inventory-full cycle always starts this phase's TargetLock clean -
    ; without this, a second cycle in the same script run (no process
    ; restart) would resume with a stale stability streak carried over
    ; from whatever rockfall was last tracked.
    ResetForNewCycle() {
        this._lock.Reset()
    }

    _Click(ctx, x, y) {
        if (this._runMode)
            Send("{Ctrl down}")

        ctx.clicker.MoveTo(x, y, 0, 0, &targetX, &targetY)
        ctx.waiter.After(ctx.timing, "clickSettle")
        ctx.clicker.Press()

        if (this._runMode) {
            ctx.waiter.After(ctx.timing, "ctrlHoldSettle")
            Send("{Ctrl up}")
        }
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "clearRed"

        if (!ctx.Get("redHasTarget", false))
            return this._Acquire(ctx)
        return this._Track(ctx)
    }

    ; Mode 1: no target locked - search the whole screen. Not found at all
    ; means no more rockfalls anywhere, so move on to clearYellow.
    _Acquire(ctx) {
        found := ColorSearch.FindFilledBlock(0, 0, A_ScreenWidth, A_ScreenHeight,
            this._color, this._tolerance, this._reqW, this._reqH, &cx, &cy)

        if (!found) {
            ctx.Log("ClearRedPhase: No red rockfalls found. Moving to hopper.")
            ctx.Set("yellowLastClickTime", 0)
            return "clearYellow"
        }

        ctx.Set("redHasTarget", true)
        ctx.Set("redTargetX", cx)
        ctx.Set("redTargetY", cy)
        ctx.Set("redLastClickTime", 0)
        this._lock.Reset()
        ctx.Log("ClearRedPhase: Found new red rockfall at [" cx ", " cy "]")
        ctx.failsafe.ResetPhaseTimer(ctx)
        return "clearRed"
    }

    ; Mode 2: target locked - re-search a narrowed box around the last
    ; known position (camera drift while running toward it).
    _Track(ctx) {
        lastX := ctx.Get("redTargetX", 0)
        lastY := ctx.Get("redTargetY", 0)

        rx1 := Max(0, lastX - this._trackBoxRadiusPx)
        ry1 := Max(0, lastY - this._trackBoxRadiusPx)
        rx2 := Min(A_ScreenWidth, lastX + this._trackBoxRadiusPx)
        ry2 := Min(A_ScreenHeight, lastY + this._trackBoxRadiusPx)

        nvx := 0, nvy := 0
        found := ColorSearch.FindFilledBlock(rx1, ry1, rx2, ry2, this._color, this._tolerance, this._reqW, this._reqH, &nvx, &nvy)
        this._lock.Observe(found, nvx, nvy, &outX, &outY)

        if (!found) {
            ctx.Log("ClearRedPhase: Rockfall cleared or lost. Scanning for another.")
            ctx.Set("redHasTarget", false)
            ctx.Set("redTargetX", 0)
            ctx.Set("redTargetY", 0)
            return "clearRed"
        }

        ctx.Set("redTargetX", outX)
        ctx.Set("redTargetY", outY)

        if (this._lock.IsStable()) {
            lastClick := ctx.Get("redLastClickTime", 0)
            if ((A_TickCount - lastClick) > this._clearCooldownMs) {
                this._Click(ctx, outX, outY)
                ctx.Set("redLastClickTime", A_TickCount)
                ctx.Log("ClearRedPhase: Failsafe click on red rockfall at [" outX ", " outY "]")
                ctx.failsafe.ResetPhaseTimer(ctx)
            }
        } else {
            lastClick := ctx.Get("redLastClickTime", 0)
            if (lastClick = 0) {
                this._Click(ctx, outX, outY)
                ctx.Set("redLastClickTime", A_TickCount)
                ctx.Log("ClearRedPhase: Initial click on red rockfall at [" outX ", " outY "]")
                ctx.failsafe.ResetPhaseTimer(ctx)
            }
        }

        return "clearRed"
    }
}

; ============================================================
; ClearYellowPhase - direct port of auto-motherlode-v2.ahk's
; ClearYellowPhase (lines 317-369). Deposits mined ore into the
; hopper. Exit check (indicator slot empty) runs FIRST every
; tick, before searching - matching legacy's exact ordering.
;
; Exit: once the ore is fully deposited, transitions to
; withdrawSack (running to the ore sack) to continue the cycle.
; ============================================================
class ClearYellowPhase extends Phase {
    __New(color, tolerance, reqW, reqH, stableTicksRequired, clickCooldownMs, runMode := false) {
        super.__New("clearYellow")
        this._color := color
        this._tolerance := tolerance
        this._reqW := reqW
        this._reqH := reqH
        this._clickCooldownMs := clickCooldownMs
        this._lock := TargetLock(stableTicksRequired, 2)
        this._runMode := runMode
    }

    ; See ClearRedPhase.ResetForNewCycle - same rationale, called by
    ; MinePhase on the mine->clearRed transition (clearYellow is entered
    ; only via clearRed, so resetting both phases' locks at that one
    ; transition point covers a fresh entry into either).
    ResetForNewCycle() {
        this._lock.Reset()
    }

    _Click(ctx, x, y) {
        if (this._runMode)
            Send("{Ctrl down}")

        ctx.clicker.MoveTo(x, y, 0, 0, &targetX, &targetY)
        ctx.waiter.After(ctx.timing, "clickSettle")
        ctx.clicker.Press()

        if (this._runMode) {
            ctx.waiter.After(ctx.timing, "ctrlHoldSettle")
            Send("{Ctrl up}")
        }
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "clearYellow"

        if (ctx.inventory.IsEmpty()) {
            ctx.Log("ClearYellowPhase: Ore deposited. Moving to sack.")
            return "withdrawSack"
        }

        found := ColorSearch.FindFilledBlock(0, 0, A_ScreenWidth, A_ScreenHeight,
            this._color, this._tolerance, this._reqW, this._reqH, &cx, &cy)

        if (!found) {
            ctx.Log("ClearYellowPhase: Cannot see hopper!")
            return "clearYellow"
        }

        this._lock.Observe(true, cx, cy, &outX, &outY)
        ctx.Set("yellowTargetX", outX)
        ctx.Set("yellowTargetY", outY)

        if (this._lock.IsStable()) {
            lastClick := ctx.Get("yellowLastClickTime", 0)
            if ((A_TickCount - lastClick) > this._clickCooldownMs) {
                this._Click(ctx, outX, outY)
                ctx.Set("yellowLastClickTime", A_TickCount)
                ctx.Log("ClearYellowPhase: Clicked hopper at [" outX ", " outY "]")
                ctx.failsafe.ResetPhaseTimer(ctx)
            }
        } else {
            lastClick := ctx.Get("yellowLastClickTime", 0)
            if (lastClick = 0) {
                this._Click(ctx, outX, outY)
                ctx.Set("yellowLastClickTime", A_TickCount)
                ctx.Log("ClearYellowPhase: Initial click to hopper at [" outX ", " outY "]")
                ctx.failsafe.ResetPhaseTimer(ctx)
            }
        }

        return "clearYellow"
    }
}

; ============================================================
; WithdrawSackPhase - direct port of auto-motherlode-v2.ahk's
; WithdrawSackPhase (lines 371-423). Clicks a fixed screen point
; to run to/interact with the ore sack, then waits for the
; inventory to receive items (checked via slot 2 OR slot 12,
; since a gem can land in either) before moving to depositBank.
;
; Exit: if the wait exceeds sackWaitTimeoutMs with no items
; received, logs and stops the engine cleanly rather than
; looping or re-clicking forever - matches the established
; fail-safely-stop pattern from earlier phases.
; ============================================================
class WithdrawSackPhase extends Phase {
    __New(sackX, sackY, preClickDelayKey, reclickCooldownMs, waitTimeoutMs, runMode := false) {
        super.__New("withdrawSack")
        this._sackX := sackX
        this._sackY := sackY
        this._preClickDelayKey := preClickDelayKey
        this._reclickCooldownMs := reclickCooldownMs
        this._waitTimeoutMs := waitTimeoutMs
        this._runMode := runMode
    }

    ResetForNewCycle() {
        ; No TargetLock here (fixed-point click, no tracking) - just the
        ; scratch timestamps, which MinePhase already resets on the
        ; mine->clearRed transition (sackLastClickTime/sackWaitStartedAt).
    }

    _Click(ctx, x, y) {
        if (this._runMode)
            Send("{Ctrl down}")

        ctx.clicker.MoveTo(x, y, 0, 0, &targetX, &targetY)
        ctx.waiter.After(ctx.timing, "clickSettle")
        ctx.clicker.Press()

        if (this._runMode) {
            ctx.waiter.After(ctx.timing, "ctrlHoldSettle")
            Send("{Ctrl up}")
        }
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "withdrawSack"

        if (ctx.inventory.HasSackItems()) {
            ctx.Log("WithdrawSackPhase: Items received from sack. Moving to bank.")
            return "depositBank"
        }

        waitStartedAt := ctx.Get("sackWaitStartedAt", 0)
        if (waitStartedAt == 0) {
            waitStartedAt := A_TickCount
            ctx.Set("sackWaitStartedAt", waitStartedAt)
        } else if ((A_TickCount - waitStartedAt) > this._waitTimeoutMs) {
            ctx.Log("WithdrawSackPhase: Timed out waiting for the sack to give items - stopping")
            ctx.engine.Stop("Timed out waiting for sack items")
            return "withdrawSack"
        }

        lastClick := ctx.Get("sackLastClickTime", 0)
        isFirstClick := (lastClick == 0)
        if (isFirstClick || (A_TickCount - lastClick) > this._reclickCooldownMs) {
            if (isFirstClick)
                ctx.waiter.After(ctx.timing, this._preClickDelayKey)

            this._Click(ctx, this._sackX, this._sackY)
            ctx.Set("sackLastClickTime", A_TickCount)
            ctx.Log("WithdrawSackPhase: Clicked sack at [" this._sackX ", " this._sackY "]")
            ctx.failsafe.ResetPhaseTimer(ctx)
        }

        return "withdrawSack"
    }
}

; ============================================================
; DepositBankPhase - direct port of auto-motherlode-v2.ahk's
; DepositBankPhase (lines 425-478). Finds and clicks the
; deposit-container (a magenta 0xFF00FF overlay marker), waits
; for the deposit box's "Deposit All" button image to appear,
; then clicks it - the terminal action of the whole mine/bank
; cycle for now, since returning to the mining spot (phase 4)
; isn't built yet.
;
; Exit: once the deposit button is clicked, logs completion and
; stops the engine cleanly (matches the established pattern -
; phase 4 doesn't exist, so this is the current end of the road)
; rather than transitioning to a phase name that doesn't exist.
; Also stops cleanly if the deposit-box image never appears
; within bankImageWaitTimeoutMs.
; ============================================================
class DepositBankPhase extends Phase {
    __New(color, tolerance, reqW, reqH, depositAnchor, imageWaitTimeoutMs, imagePollKey, preClickDelayKey, runMode := false) {
        super.__New("depositBank")
        this._color := color
        this._tolerance := tolerance
        this._reqW := reqW
        this._reqH := reqH
        this._depositAnchor := depositAnchor   ; an ImageAnchor for deposit-motherlode.png
        this._imageWaitTimeoutMs := imageWaitTimeoutMs
        this._imagePollKey := imagePollKey
        this._preClickDelayKey := preClickDelayKey
        this._runMode := runMode
    }

    ResetForNewCycle() {
        ; bankPreDelayApplied (the one-time settle-delay flag) is reset by
        ; MinePhase's mine->clearRed transition, alongside its other
        ; per-cycle scratch state.
    }

    _Click(ctx, x, y) {
        if (this._runMode)
            Send("{Ctrl down}")

        ctx.clicker.MoveTo(x, y, 0, 0, &targetX, &targetY)
        ctx.waiter.After(ctx.timing, "clickSettle")
        ctx.clicker.Press()

        if (this._runMode) {
            ctx.waiter.After(ctx.timing, "ctrlHoldSettle")
            Send("{Ctrl up}")
        }
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "depositBank"

        ; One-time settle delay on first entry into this phase, BEFORE
        ; searching - not after. Searching first and sleeping afterward
        ; would click the coordinates found before the sleep, which go
        ; stale while the character/camera is still moving (arriving
        ; fresh from the sack), causing the click to land on whatever
        ; happens to be at that old screen position instead of the
        ; deposit container. Waiting first, then searching and clicking
        ; immediately with no gap in between, guarantees the click always
        ; targets a position found right now - same principle MinePhase/
        ; ClearRedPhase/ClearYellowPhase already follow (never sleep
        ; between finding a target and clicking it).
        if (!ctx.Get("bankPreDelayApplied", false)) {
            ctx.waiter.After(ctx.timing, this._preClickDelayKey)
            ctx.Set("bankPreDelayApplied", true)
        }

        found := ColorSearch.FindFilledBlock(0, 0, A_ScreenWidth, A_ScreenHeight,
            this._color, this._tolerance, this._reqW, this._reqH, &cx, &cy)

        if (!found) {
            ctx.Log("DepositBankPhase: Cannot see deposit container!")
            return "depositBank"
        }

        ctx.Log("DepositBankPhase: Clicked deposit container at [" cx ", " cy "]")
        this._Click(ctx, cx, cy)
        ctx.failsafe.ResetPhaseTimer(ctx)

        ctx.Log("DepositBankPhase: Waiting for deposit box to open...")
        if (!this._depositAnchor.WaitFor(ctx.waiter, ctx.timing, this._imagePollKey, this._imageWaitTimeoutMs, &dx, &dy)) {
            ctx.Log("DepositBankPhase: Timed out waiting for deposit box - stopping")
            ctx.engine.Stop("Timed out waiting for deposit box")
            return "depositBank"
        }

        this._Click(ctx, dx, dy)
        ctx.Log("DepositBankPhase: Deposited all - banking complete, returning to mine")
        return "returnMine1"
    }
}

; ============================================================
; ReturnMine1Phase - step 1 of walking from the bank back to the
; mining spot. Clicks a fixed screen point once, then waits for
; an orange (0xFF8700) waypoint-arrival marker to appear in a
; padded region around a calibrated point, with a re-click
; failsafe if the marker doesn't appear within a cooldown of the
; last click. Direct analog of auto-motherlode-v2.ahk's
; ReturnMine1Phase (lines 480-516), just without the extra
; settle-sleep legacy had after finding the marker (not part of
; this user's spec).
;
; Exit: transitions to returnMine2 once the marker is found. If
; the marker never appears within return1WaitTimeoutMs, logs and
; stops the engine cleanly (same pattern as every other phase's
; internal wait failsafe).
; ============================================================
class ReturnMine1Phase extends Phase {
    __New(clickX, clickY, markerX, markerY, markerW, markerH, markerColor, markerTolerance, searchPaddingPx, reclickCooldownMs, waitTimeoutMs, runMode := false) {
        super.__New("returnMine1")
        this._clickX := clickX
        this._clickY := clickY
        this._markerX := markerX
        this._markerY := markerY
        this._markerW := markerW
        this._markerH := markerH
        this._markerColor := markerColor
        this._markerTolerance := markerTolerance
        this._searchPaddingPx := searchPaddingPx
        this._reclickCooldownMs := reclickCooldownMs
        this._waitTimeoutMs := waitTimeoutMs
        this._runMode := runMode
    }

    ResetForNewCycle() {
        ; Scratch timestamps (return1LastClickTime/return1WaitStartedAt) are
        ; reset by ReturnMine2Phase's stage-2 full-cycle reset, alongside
        ; every other phase's per-cycle state.
    }

    _Click(ctx, x, y) {
        if (this._runMode)
            Send("{Ctrl down}")

        ctx.clicker.MoveTo(x, y, 0, 0, &targetX, &targetY)
        ctx.waiter.After(ctx.timing, "clickSettle")
        ctx.clicker.Press()

        if (this._runMode) {
            ctx.waiter.After(ctx.timing, "ctrlHoldSettle")
            Send("{Ctrl up}")
        }
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "returnMine1"

        rx1 := Max(0, this._markerX - this._searchPaddingPx)
        ry1 := Max(0, this._markerY - this._searchPaddingPx)
        rx2 := Min(A_ScreenWidth, this._markerX + this._searchPaddingPx)
        ry2 := Min(A_ScreenHeight, this._markerY + this._searchPaddingPx)

        found := ColorSearch.FindFilledBlock(rx1, ry1, rx2, ry2,
            this._markerColor, this._markerTolerance, this._markerW, this._markerH, &cx, &cy)

        if (found) {
            ctx.Log("ReturnMine1Phase: Arrived at waypoint 1!")
            ; Settle delay before handing off - without this, returnMine2's
            ; very next tick would click the step-2 waypoint instantly,
            ; before the character has actually finished arriving here.
            ctx.waiter.After(ctx.timing, "return1PostMarkerDelay")
            return "returnMine2"
        }

        waitStartedAt := ctx.Get("return1WaitStartedAt", 0)
        if (waitStartedAt == 0) {
            ctx.Set("return1WaitStartedAt", A_TickCount)
        } else if ((A_TickCount - waitStartedAt) > this._waitTimeoutMs) {
            ctx.Log("ReturnMine1Phase: Timed out waiting for waypoint 1 marker - stopping")
            ctx.engine.Stop("Timed out waiting for return waypoint 1")
            return "returnMine1"
        }

        lastClick := ctx.Get("return1LastClickTime", 0)
        if (lastClick == 0 || (A_TickCount - lastClick) > this._reclickCooldownMs) {
            this._Click(ctx, this._clickX, this._clickY)
            ctx.Set("return1LastClickTime", A_TickCount)
            ctx.Log("ReturnMine1Phase: Clicked waypoint 1 at [" this._clickX ", " this._clickY "]")
            ctx.failsafe.ResetPhaseTimer(ctx)
        }

        return "returnMine1"
    }
}

; ============================================================
; ReturnMine2Phase - step 2 (walk + marker wait) and the final
; approach click, combined as a 2-stage internal state machine
; reported externally as the single phase "returnMine2" (matches
; legacy's own internal-substage-under-one-phase-name pattern).
;
; Stage 1: click the step-2 point, wait for its orange marker
; (same click/wait/failsafe shape as ReturnMine1Phase).
; Stage 2: click the final fixed mine-spot point, wait
; return2AfterClickWaitMs, then do a full per-cycle state reset
; (mirroring legacy's ResetBotState()) and hand off to "mine" -
; the completion of the entire mine/bank/return loop.
; ============================================================
class ReturnMine2Phase extends Phase {
    __New(clickX, clickY, markerX, markerY, markerW, markerH, markerColor, markerTolerance, searchPaddingPx, reclickCooldownMs, waitTimeoutMs, finalClickX, finalClickY, afterClickWaitMs, nextCyclePhases, runMode := false) {
        super.__New("returnMine2")
        this._clickX := clickX
        this._clickY := clickY
        this._markerX := markerX
        this._markerY := markerY
        this._markerW := markerW
        this._markerH := markerH
        this._markerColor := markerColor
        this._markerTolerance := markerTolerance
        this._searchPaddingPx := searchPaddingPx
        this._reclickCooldownMs := reclickCooldownMs
        this._waitTimeoutMs := waitTimeoutMs
        this._finalClickX := finalClickX
        this._finalClickY := finalClickY
        this._afterClickWaitMs := afterClickWaitMs
        this._nextCyclePhases := nextCyclePhases
        this._runMode := runMode
    }

    ResetForNewCycle() {
        ; return2Stage/return2LastClickTime/return2WaitStartedAt are reset
        ; by this phase's own stage-2 completion (the one place a fresh
        ; cycle actually begins) - nothing to do here.
    }

    _Click(ctx, x, y) {
        if (this._runMode)
            Send("{Ctrl down}")

        ctx.clicker.MoveTo(x, y, 0, 0, &targetX, &targetY)
        ctx.waiter.After(ctx.timing, "clickSettle")
        ctx.clicker.Press()

        if (this._runMode) {
            ctx.waiter.After(ctx.timing, "ctrlHoldSettle")
            Send("{Ctrl up}")
        }
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "returnMine2"

        stage := ctx.Get("return2Stage", 1)
        if (stage == 1)
            return this._Stage1(ctx)
        return this._Stage2(ctx)
    }

    ; Stage 1: click the step-2 waypoint, wait for its marker - identical
    ; shape to ReturnMine1Phase.
    _Stage1(ctx) {
        rx1 := Max(0, this._markerX - this._searchPaddingPx)
        ry1 := Max(0, this._markerY - this._searchPaddingPx)
        rx2 := Min(A_ScreenWidth, this._markerX + this._searchPaddingPx)
        ry2 := Min(A_ScreenHeight, this._markerY + this._searchPaddingPx)

        found := ColorSearch.FindFilledBlock(rx1, ry1, rx2, ry2,
            this._markerColor, this._markerTolerance, this._markerW, this._markerH, &cx, &cy)

        if (found) {
            ctx.Log("ReturnMine2Phase: Saw waypoint 2 marker. Moving to final approach.")
            ; Settle delay before advancing - without this, stage 2 would
            ; fire the final approach click instantly on the very next tick.
            ctx.waiter.After(ctx.timing, "return2PostMarkerDelay")
            ctx.Set("return2Stage", 2)
            ctx.Set("return2LastClickTime", 0)
            return "returnMine2"
        }

        waitStartedAt := ctx.Get("return2WaitStartedAt", 0)
        if (waitStartedAt == 0) {
            ctx.Set("return2WaitStartedAt", A_TickCount)
        } else if ((A_TickCount - waitStartedAt) > this._waitTimeoutMs) {
            ctx.Log("ReturnMine2Phase: Timed out waiting for waypoint 2 marker - stopping")
            ctx.engine.Stop("Timed out waiting for return waypoint 2")
            return "returnMine2"
        }

        lastClick := ctx.Get("return2LastClickTime", 0)
        if (lastClick == 0 || (A_TickCount - lastClick) > this._reclickCooldownMs) {
            this._Click(ctx, this._clickX, this._clickY)
            ctx.Set("return2LastClickTime", A_TickCount)
            ctx.Log("ReturnMine2Phase: Clicked waypoint 2 at [" this._clickX ", " this._clickY "]")
            ctx.failsafe.ResetPhaseTimer(ctx)
        }

        return "returnMine2"
    }

    ; Stage 2: click the final mine-spot point once, wait
    ; afterClickWaitMs, then fully reset per-cycle state and hand off to
    ; "mine" - the completion of the whole loop.
    _Stage2(ctx) {
        lastClick := ctx.Get("return2LastClickTime", 0)
        if (lastClick == 0) {
            this._Click(ctx, this._finalClickX, this._finalClickY)
            ctx.Set("return2LastClickTime", A_TickCount)
            ctx.Log("ReturnMine2Phase: Clicked final approach spot at [" this._finalClickX ", " this._finalClickY "]")
            ctx.failsafe.ResetPhaseTimer(ctx)
            return "returnMine2"
        }

        if ((A_TickCount - lastClick) < this._afterClickWaitMs)
            return "returnMine2"

        ctx.Log("ReturnMine2Phase: Wait complete. Handing off to mine phase.")

        ; Full per-cycle reset, mirroring legacy's ResetBotState() right
        ; before handing off to "mine" - without this, a second full
        ; mine->bank->return cycle in the same script run would resume
        ; every phase with stale target coordinates/timestamps/stability
        ; streaks left over from the first cycle.
        ctx.Set("mineHasTarget", false)
        ctx.Set("mineTargetX", 0)
        ctx.Set("mineTargetY", 0)
        ctx.Set("mineLastClickTime", 0)
        ctx.Set("redHasTarget", false)
        ctx.Set("redTargetX", 0)
        ctx.Set("redTargetY", 0)
        ctx.Set("redLastClickTime", 0)
        ctx.Set("yellowTargetX", 0)
        ctx.Set("yellowTargetY", 0)
        ctx.Set("yellowLastClickTime", 0)
        ctx.Set("sackLastClickTime", 0)
        ctx.Set("sackWaitStartedAt", 0)
        ctx.Set("bankPreDelayApplied", false)
        ctx.Set("return1LastClickTime", 0)
        ctx.Set("return1WaitStartedAt", 0)
        ctx.Set("return2Stage", 1)
        ctx.Set("return2LastClickTime", 0)
        ctx.Set("return2WaitStartedAt", 0)
        for phase in this._nextCyclePhases
            phase.ResetForNewCycle()

        return "mine"
    }
}

; ============================================================
; Wiring
; ============================================================

; --- Config schema: every .ini key this bot needs, declared up front ---
; Fails fast at Load() if any of these are missing from the .ini - no
; silent fallback to a code-side default (ruleset 3.6).
schema := Map(
    "runnerTickMs", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutMine", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutBank", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutSack", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutReturn", Map("section", "Tunables", "type", "int"),
    "colorTolerance", Map("section", "Tunables", "type", "int"),
    "mineStableTicks", Map("section", "Tunables", "type", "int"),
    "veinClickOffsetX", Map("section", "Tunables", "type", "int"),
    "veinClickOffsetY", Map("section", "Tunables", "type", "int"),
    "mineScanBottomUp", Map("section", "Tunables", "type", "int"),
    "walkReclickTimeoutMs", Map("section", "Tunables", "type", "int"),
    "mineRegionX1", Map("section", "Tunables", "type", "int"),
    "mineRegionY1", Map("section", "Tunables", "type", "int"),
    "mineRegionX2", Map("section", "Tunables", "type", "int"),
    "mineRegionY2", Map("section", "Tunables", "type", "int"),
    "veinColorLight", Map("section", "Tunables", "type", "color"),
    "veinColorDark", Map("section", "Tunables", "type", "color"),
    "mineBlockW", Map("section", "Tunables", "type", "int"),
    "mineBlockH", Map("section", "Tunables", "type", "int"),
    "referencePointX", Map("section", "Tunables", "type", "int"),
    "referencePointY", Map("section", "Tunables", "type", "int"),
    "runMode", Map("section", "Settings", "type", "int"),
    "indicatorSlot", Map("section", "Settings", "type", "int"),
    "secondaryIndicatorSlot", Map("section", "Settings", "type", "int"),
    "redColor", Map("section", "Tunables", "type", "color"),
    "redTolerance", Map("section", "Tunables", "type", "int"),
    "redBlockW", Map("section", "Tunables", "type", "int"),
    "redBlockH", Map("section", "Tunables", "type", "int"),
    "redTrackBoxRadiusPx", Map("section", "Tunables", "type", "int"),
    "redStableTicks", Map("section", "Tunables", "type", "int"),
    "redClearCooldownMs", Map("section", "Tunables", "type", "int"),
    "yellowColor", Map("section", "Tunables", "type", "color"),
    "yellowTolerance", Map("section", "Tunables", "type", "int"),
    "yellowBlockW", Map("section", "Tunables", "type", "int"),
    "yellowBlockH", Map("section", "Tunables", "type", "int"),
    "yellowStableTicks", Map("section", "Tunables", "type", "int"),
    "yellowClickCooldownMs", Map("section", "Tunables", "type", "int"),
    "sackRunX", Map("section", "Tunables", "type", "int"),
    "sackRunY", Map("section", "Tunables", "type", "int"),
    "sackReclickCooldownMs", Map("section", "Tunables", "type", "int"),
    "sackWaitTimeoutMs", Map("section", "Tunables", "type", "int"),
    "bankColor", Map("section", "Tunables", "type", "color"),
    "bankTolerance", Map("section", "Tunables", "type", "int"),
    "bankBlockW", Map("section", "Tunables", "type", "int"),
    "bankBlockH", Map("section", "Tunables", "type", "int"),
    "bankImageAnchorX", Map("section", "Tunables", "type", "int"),
    "bankImageAnchorY", Map("section", "Tunables", "type", "int"),
    "bankImageSearchPaddingPx", Map("section", "Tunables", "type", "int"),
    "bankImageWaitTimeoutMs", Map("section", "Tunables", "type", "int"),
    "sackGateSlotA", Map("section", "Settings", "type", "int"),
    "sackGateSlotB", Map("section", "Settings", "type", "int"),
    "return1ClickX", Map("section", "Tunables", "type", "int"),
    "return1ClickY", Map("section", "Tunables", "type", "int"),
    "return1MarkerX", Map("section", "Tunables", "type", "int"),
    "return1MarkerY", Map("section", "Tunables", "type", "int"),
    "return1MarkerW", Map("section", "Tunables", "type", "int"),
    "return1MarkerH", Map("section", "Tunables", "type", "int"),
    "return1MarkerColor", Map("section", "Tunables", "type", "color"),
    "return1MarkerTolerance", Map("section", "Tunables", "type", "int"),
    "return1MarkerSearchPaddingPx", Map("section", "Tunables", "type", "int"),
    "return1ReclickCooldownMs", Map("section", "Tunables", "type", "int"),
    "return1WaitTimeoutMs", Map("section", "Tunables", "type", "int"),
    "return2ClickX", Map("section", "Tunables", "type", "int"),
    "return2ClickY", Map("section", "Tunables", "type", "int"),
    "return2MarkerX", Map("section", "Tunables", "type", "int"),
    "return2MarkerY", Map("section", "Tunables", "type", "int"),
    "return2MarkerW", Map("section", "Tunables", "type", "int"),
    "return2MarkerH", Map("section", "Tunables", "type", "int"),
    "return2MarkerColor", Map("section", "Tunables", "type", "color"),
    "return2MarkerTolerance", Map("section", "Tunables", "type", "int"),
    "return2MarkerSearchPaddingPx", Map("section", "Tunables", "type", "int"),
    "return2ReclickCooldownMs", Map("section", "Tunables", "type", "int"),
    "return2WaitTimeoutMs", Map("section", "Tunables", "type", "int"),
    "return2FinalClickX", Map("section", "Tunables", "type", "int"),
    "return2FinalClickY", Map("section", "Tunables", "type", "int"),
    "return2AfterClickWaitMs", Map("section", "Tunables", "type", "int")
)
timingSchema := Map(
    "mineClickCooldown", Map("section", "Tunables", "baseMsKey", "clickCooldownMs"),
    "clickSettle", Map("section", "Tunables", "baseMsKey", "clickSettleMs", "jitterPercentKey", "clickSettleJitterPercent"),
    "ctrlHoldSettle", Map("section", "Tunables", "baseMsKey", "ctrlHoldSettleMs", "jitterPercentKey", "clickSettleJitterPercent"),
    "sackPreClickDelay", Map("section", "Tunables", "baseMsKey", "sackPreClickDelayMs"),
    "bankImagePoll", Map("section", "Tunables", "baseMsKey", "bankImagePollMs"),
    "bankPreClickDelay", Map("section", "Tunables", "baseMsKey", "bankPreClickDelayMs"),
    "return1PostMarkerDelay", Map("section", "Tunables", "baseMsKey", "return1PostMarkerDelayMs"),
    "return2PostMarkerDelay", Map("section", "Tunables", "baseMsKey", "return2PostMarkerDelayMs")
)

iniPath := A_ScriptDir "\..\..\config\auto-motherlode-v2.ini"
botConfig := Config(iniPath, schema, timingSchema)
botConfig.Load()

botLogger := Logger(A_ScriptDir "\..\..\logs\auto-motherlode-v4-debug.log")
botHumanizer := Humanizer(false)
botClicker := Clicker(botHumanizer)
botFailsafe := FailSafe(botLogger)
botWaiter := Waiter((baseMs, jitterPercent) => botHumanizer.Jitter(baseMs, jitterPercent))
botWindowFocus := WindowFocus()
botOverlay := Overlay(8, 10, 10)

ctx := EngineContext(botConfig, botLogger, botClicker, botFailsafe, botWaiter, botWindowFocus, botOverlay)

; --- Inventory: this user's measured layout - a fixed property of this
; client window (not a game-state tunable), so it's a hardcoded constant
; here rather than an .ini key, matching how legacy's lib/Grid.ahk treats
; INVENTORY_FIRST_X etc. as hardcoded module-level constants. Recalibrate
; this Map directly if the client window ever moves/resizes. Only the
; DETECTION tuning (colorTolerance, indicatorSlot) is .ini-configurable. ---
inventoryLayout := Map("firstX", 2099, "firstY", 801, "cols", 4, "rows", 7, "slotW", 72, "slotH", 64, "gapX", 12, "gapY", 8)
ctx.inventory := Inventory(inventoryLayout)
; Full requires BOTH indicatorSlot (28) AND secondaryIndicatorSlot (27)
; occupied - a lone gem can land in slot 28 without the hopper ever
; collecting it (gems aren't ore), which would make a 28-only check
; falsely report "full" forever after a single gem. Requiring 27 too
; means a gem alone in 28 (with 27 still empty) correctly reads as not
; full, and "empty" (the clearYellow exit) is just the inverse of this
; same combined gate.
indicatorGate := SlotGate(botConfig.Get("indicatorSlot"), botConfig.Get("colorTolerance"), ctx.inventory)
secondaryIndicatorGate := SlotGate(botConfig.Get("secondaryIndicatorSlot"), botConfig.Get("colorTolerance"), ctx.inventory)
fullGate := AndGate([indicatorGate, secondaryIndicatorGate])
ctx.inventory.SetFullGate(fullGate)
ctx.inventory.SetEmptyGate(NotGate(fullGate))
; "Sack gave us something" - true if EITHER of two spread-out slots is
; occupied, since a gem can land in any slot (WithdrawSackPhase's exit
; check).
sackGateA := SlotGate(botConfig.Get("sackGateSlotA"), botConfig.Get("colorTolerance"), ctx.inventory)
sackGateB := SlotGate(botConfig.Get("sackGateSlotB"), botConfig.Get("colorTolerance"), ctx.inventory)
ctx.inventory.SetSackGate(OrGate([sackGateA, sackGateB]))

; --- Mine phase wiring - every value below now comes from the .ini
; (see [Tunables] mineRegionX1/Y1/X2/Y2, veinColorLight/Dark, mineBlockW/H,
; referencePointX/Y) rather than being hardcoded here. ---
mineRegion := Map("x1", botConfig.Get("mineRegionX1"), "y1", botConfig.Get("mineRegionY1"), "x2", botConfig.Get("mineRegionX2"), "y2", botConfig.Get("mineRegionY2"))
veinColors := [botConfig.Get("veinColorLight"), botConfig.Get("veinColorDark")]
referencePoint := Map("x", botConfig.Get("referencePointX"), "y", botConfig.Get("referencePointY"))

botClearRedPhase := ClearRedPhase(
    botConfig.Get("redColor"), botConfig.Get("redTolerance"),
    botConfig.Get("redBlockW"), botConfig.Get("redBlockH"),
    botConfig.Get("redTrackBoxRadiusPx"), botConfig.Get("redStableTicks"),
    botConfig.Get("redClearCooldownMs"), botConfig.Get("runMode")
)

botClearYellowPhase := ClearYellowPhase(
    botConfig.Get("yellowColor"), botConfig.Get("yellowTolerance"),
    botConfig.Get("yellowBlockW"), botConfig.Get("yellowBlockH"),
    botConfig.Get("yellowStableTicks"), botConfig.Get("yellowClickCooldownMs"),
    botConfig.Get("runMode")
)

botWithdrawSackPhase := WithdrawSackPhase(
    botConfig.Get("sackRunX"), botConfig.Get("sackRunY"),
    "sackPreClickDelay", botConfig.Get("sackReclickCooldownMs"),
    botConfig.Get("sackWaitTimeoutMs"), botConfig.Get("runMode")
)

; --- Deposit box "Deposit All" button image anchor - calibrated region is
; bankImageAnchorX/Y padded by bankImageSearchPaddingPx in every direction,
; matching legacy's padded-box approach around its own calibrated image
; position. deposit-motherlode.png is 80x72px (confirmed on disk). ---
depositImagePath := A_ScriptDir "\..\..\Images\deposit-motherlode.png"
depositImageRegion := Map(
    "x1", botConfig.Get("bankImageAnchorX") - botConfig.Get("bankImageSearchPaddingPx"),
    "y1", botConfig.Get("bankImageAnchorY") - botConfig.Get("bankImageSearchPaddingPx"),
    "x2", botConfig.Get("bankImageAnchorX") + 80 + botConfig.Get("bankImageSearchPaddingPx"),
    "y2", botConfig.Get("bankImageAnchorY") + 72 + botConfig.Get("bankImageSearchPaddingPx")
)
depositAnchor := ImageAnchor(depositImageRegion, depositImagePath, 80, 72)

botDepositBankPhase := DepositBankPhase(
    botConfig.Get("bankColor"), botConfig.Get("bankTolerance"),
    botConfig.Get("bankBlockW"), botConfig.Get("bankBlockH"),
    depositAnchor, botConfig.Get("bankImageWaitTimeoutMs"), "bankImagePoll",
    "bankPreClickDelay", botConfig.Get("runMode")
)

nextCyclePhases := [botClearRedPhase, botClearYellowPhase, botWithdrawSackPhase, botDepositBankPhase]

botReturnMine1Phase := ReturnMine1Phase(
    botConfig.Get("return1ClickX"), botConfig.Get("return1ClickY"),
    botConfig.Get("return1MarkerX"), botConfig.Get("return1MarkerY"),
    botConfig.Get("return1MarkerW"), botConfig.Get("return1MarkerH"),
    botConfig.Get("return1MarkerColor"), botConfig.Get("return1MarkerTolerance"),
    botConfig.Get("return1MarkerSearchPaddingPx"), botConfig.Get("return1ReclickCooldownMs"),
    botConfig.Get("return1WaitTimeoutMs"), botConfig.Get("runMode")
)
nextCyclePhases.Push(botReturnMine1Phase)

botReturnMine2Phase := ReturnMine2Phase(
    botConfig.Get("return2ClickX"), botConfig.Get("return2ClickY"),
    botConfig.Get("return2MarkerX"), botConfig.Get("return2MarkerY"),
    botConfig.Get("return2MarkerW"), botConfig.Get("return2MarkerH"),
    botConfig.Get("return2MarkerColor"), botConfig.Get("return2MarkerTolerance"),
    botConfig.Get("return2MarkerSearchPaddingPx"), botConfig.Get("return2ReclickCooldownMs"),
    botConfig.Get("return2WaitTimeoutMs"), botConfig.Get("return2FinalClickX"), botConfig.Get("return2FinalClickY"),
    botConfig.Get("return2AfterClickWaitMs"), nextCyclePhases, botConfig.Get("runMode")
)
nextCyclePhases.Push(botReturnMine2Phase)

botMinePhase := MinePhase(
    mineRegion, veinColors, referencePoint,
    botConfig.Get("colorTolerance"), botConfig.Get("mineBlockW"), botConfig.Get("mineBlockH"),
    50,   ; trackBoxRadiusPx - legacy's 100x100 box = +/-50
    botConfig.Get("mineStableTicks"),
    botConfig.Get("runMode"),
    botConfig.Get("veinClickOffsetX"),
    botConfig.Get("veinClickOffsetY"),
    botConfig.Get("mineScanBottomUp") != 0,
    botConfig.Get("walkReclickTimeoutMs"),
    nextCyclePhases
)

botEngine := Engine(ctx, botConfig.Get("runnerTickMs"))
ctx.engine := botEngine
botEngine.AddPhase(botMinePhase, botConfig.Get("phaseTimeoutMine"))
botEngine.AddPhase(botClearRedPhase, botConfig.Get("phaseTimeoutBank"))
botEngine.AddPhase(botClearYellowPhase, botConfig.Get("phaseTimeoutBank"))
botEngine.AddPhase(botWithdrawSackPhase, botConfig.Get("phaseTimeoutSack"))
botEngine.AddPhase(botDepositBankPhase, botConfig.Get("phaseTimeoutSack"))
botEngine.AddPhase(botReturnMine1Phase, botConfig.Get("phaseTimeoutReturn"))
botEngine.AddPhase(botReturnMine2Phase, botConfig.Get("phaseTimeoutReturn"))

F5:: botEngine.Start("mine")
F6:: {
    botEngine.Stop("Stopped (F6)")
    botOverlay.Clear()
}
