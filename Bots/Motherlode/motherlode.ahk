; ============================================================
; motherlode.ahk
; v4 entry point + all Motherlode Mine phases, one file (single
; bot/single loop, so no benefit to splitting entry point from
; phases). Shared framework classes stay in their own files.
;
; Isolation: reads/writes only v4's own config/ and logs/ - never
; the legacy repo-root config/ or logs/ folders.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

; AHK v2 defaults Click/MouseMove/PixelSearch to "Client" coords
; (relative to the focused window). Every coordinate in v4 is
; absolute screen space, so force "Screen" mode - matches legacy.
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
; MinePhase - finds and mines veins.
;
; Mode 1 - ACQUIRE (mineHasTarget=false): search the full region
; for both vein overlay colors; if both are visible, pick
; whichever is closer to the reference point.
;
; Mode 2 - TRACK (mineHasTarget=true): re-search a narrowed box
; around the last known position, locked to the same color.
; Stability gates click cadence; a lost target resets to Mode 1.
; ============================================================
class MinePhase extends Phase {
    ; region: {x1,y1,x2,y2} vein search area.
    ; veinColors: [light, dark] overlay color candidates.
    ; referencePoint: {x,y}, used to pick between two visible veins.
    ; reqW/reqH: min solid block size to count as a vein.
    ; trackBoxRadiusPx: half-width of the tracking box once locked.
    ; clickOffsetX/Y: click offset applied after the block center is
    ; found, since the rock can sit off from the overlay's center.
    ; scanBottomUp: scan the region bottom-up instead of top-down.
    ; walkReclickTimeoutMs: re-click if still not stable after this
    ; long, so jitter can't strand the click at exactly one attempt.
    ; nextCyclePhases: every phase whose per-cycle state this phase
    ; resets on the mine->clearRed transition (see ResetForNewCycle).
    __New(region, veinColors, referencePoint, tolerance, reqW, reqH, trackBoxRadiusPx, stableTicksRequired, moveTolerancePx, runMode := false, clickOffsetX := 0, clickOffsetY := 0, scanBottomUp := false, walkReclickTimeoutMs := 3000, nextCyclePhases := "") {
        super.__New("mine")
        this._region := region
        this._veinColors := veinColors
        this._referencePoint := referencePoint
        this._tolerance := tolerance
        this._reqW := reqW
        this._reqH := reqH
        this._trackBoxRadiusPx := trackBoxRadiusPx
        this._lock := TargetLock(stableTicksRequired, moveTolerancePx)
        this._runMode := runMode
        this._clickOffsetX := clickOffsetX
        this._clickOffsetY := clickOffsetY
        this._scanBottomUp := scanBottomUp
        this._walkReclickTimeoutMs := walkReclickTimeoutMs
        this._nextCyclePhases := nextCyclePhases != "" ? nextCyclePhases : []
    }

    ; Applies the configured click offset, then delegates to the shared
    ; settled click. Returns the actual clicked point via out-params so
    ; callers can log what was really clicked.
    _Click(ctx, x, y, &clickX, &clickY) {
        clickX := x + this._clickOffsetX
        clickY := y + this._clickOffsetY
        ctx.clicker.ClickSettled(ctx, clickX, clickY, this._runMode)
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "mine"

        if (ctx.inventory.IsFull()) {
            ctx.Log("MinePhase: Inventory full, transitioning to clearRed")
            ; Reset every downstream phase's per-cycle state here, so a
            ; second full-inventory cycle in the same run doesn't resume
            ; with stale coordinates/timestamps from the first one.
            ctx.Set("redHasTarget", false)
            ctx.Set("redTargetX", 0)
            ctx.Set("redTargetY", 0)
            ctx.Set("redLastClickTime", 0)
            ctx.Set("yellowTargetX", 0)
            ctx.Set("yellowTargetY", 0)
            ctx.Set("yellowLastClickTime", 0)
            ctx.Set("yellowEntryDelayApplied", false)
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

    ; Mode 1: search for both candidate colors, pick whichever is
    ; closer to the reference point if both are present.
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

        ; Don't click on this same tick - the overlay may not be fully
        ; rendered yet, so a click here can miss the actual clickable
        ; rock. _Track's next-tick branch fires the real first click.
        ctx.failsafe.ResetPhaseTimer(ctx)
        return "mine"
    }

    ; Mode 2: re-search a narrowed box around the last known position,
    ; locked to the same color. Position always updates live; stability
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
            ; Non-blocking cooldown check, never a Sleep.
            lastClick := ctx.Get("mineLastClickTime", 0)
            if ((A_TickCount - lastClick) > ctx.timing.BaseMs("mineClickCooldown")) {
                this._Click(ctx, outX, outY, &clickX, &clickY)
                ctx.Set("mineLastClickTime", A_TickCount)
                ctx.Log("MinePhase: Clicked stable vein at [" clickX ", " clickY "] (vein at [" outX ", " outY "])")
                ctx.failsafe.ResetPhaseTimer(ctx)
            }
        } else {
            ; Not yet stable - click once immediately, then re-click if
            ; still not stable after walkReclickTimeoutMs (prevents
            ; getting stuck if the position keeps jittering).
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
; ClearRedPhase - clears rockfall obstacles blocking the hopper
; walkway. Same acquire/track shape as MinePhase, but searches
; the whole screen (a rockfall can appear anywhere), one color,
; no click offset.
;
; Exit: a full-screen search comes back empty (no target locked)
; -> no more rockfalls -> transition to clearYellow.
; ============================================================
class ClearRedPhase extends Phase {
    __New(color, tolerance, reqW, reqH, trackBoxRadiusPx, stableTicksRequired, clearCooldownMs, moveTolerancePx, runMode := false) {
        super.__New("clearRed")
        this._color := color
        this._tolerance := tolerance
        this._reqW := reqW
        this._reqH := reqH
        this._trackBoxRadiusPx := trackBoxRadiusPx
        this._clearCooldownMs := clearCooldownMs
        this._lock := TargetLock(stableTicksRequired, moveTolerancePx)
        this._runMode := runMode
    }

    ; Called on the mine->clearRed transition so a fresh cycle starts
    ; this phase's TargetLock clean, not with a stale stability streak.
    ResetForNewCycle() {
        this._lock.Reset()
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "clearRed"

        if (!ctx.Get("redHasTarget", false))
            return this._Acquire(ctx)
        return this._Track(ctx)
    }

    ; Mode 1: no target locked - search the whole screen. Not found at
    ; all means no more rockfalls, so move on to clearYellow.
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
                ctx.clicker.ClickSettled(ctx, outX, outY, this._runMode)
                ctx.Set("redLastClickTime", A_TickCount)
                ctx.Log("ClearRedPhase: Failsafe click on red rockfall at [" outX ", " outY "]")
                ctx.failsafe.ResetPhaseTimer(ctx)
            }
        } else {
            lastClick := ctx.Get("redLastClickTime", 0)
            if (lastClick = 0) {
                ctx.clicker.ClickSettled(ctx, outX, outY, this._runMode)
                ctx.Set("redLastClickTime", A_TickCount)
                ctx.Log("ClearRedPhase: Initial click on red rockfall at [" outX ", " outY "]")
                ctx.failsafe.ResetPhaseTimer(ctx)
            }
        }

        return "clearRed"
    }
}

; ============================================================
; ClearYellowPhase - deposits mined ore into the hopper. Exit
; check (inventory empty) runs first every tick, before searching.
;
; Exit: once the ore is fully deposited, transitions to
; withdrawSack to continue the cycle.
; ============================================================
class ClearYellowPhase extends Phase {
    __New(color, tolerance, reqW, reqH, stableTicksRequired, clickCooldownMs, entryDelayKey, moveTolerancePx, runMode := false) {
        super.__New("clearYellow")
        this._color := color
        this._tolerance := tolerance
        this._reqW := reqW
        this._reqH := reqH
        this._clickCooldownMs := clickCooldownMs
        this._entryDelayKey := entryDelayKey
        this._lock := TargetLock(stableTicksRequired, moveTolerancePx)
        this._runMode := runMode
    }

    ; Called by MinePhase on the mine->clearRed transition - clearYellow
    ; is only entered via clearRed, so resetting both locks there covers
    ; a fresh entry into either.
    ResetForNewCycle() {
        this._lock.Reset()
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

        ; One-time settle delay on the first tick the hopper is found -
        ; yellowStableTicks=0 makes it "instantly stable", so without
        ; this the first click fires as fast as the search resolves.
        if (!ctx.Get("yellowEntryDelayApplied", false)) {
            ctx.waiter.After(ctx.timing, this._entryDelayKey)
            ctx.Set("yellowEntryDelayApplied", true)
        }

        if (this._lock.IsStable()) {
            lastClick := ctx.Get("yellowLastClickTime", 0)
            if ((A_TickCount - lastClick) > this._clickCooldownMs) {
                ctx.clicker.ClickSettled(ctx, outX, outY, this._runMode)
                ctx.Set("yellowLastClickTime", A_TickCount)
                ctx.Log("ClearYellowPhase: Clicked hopper at [" outX ", " outY "]")
                ctx.failsafe.ResetPhaseTimer(ctx)
            }
        } else {
            lastClick := ctx.Get("yellowLastClickTime", 0)
            if (lastClick = 0) {
                ctx.clicker.ClickSettled(ctx, outX, outY, this._runMode)
                ctx.Set("yellowLastClickTime", A_TickCount)
                ctx.Log("ClearYellowPhase: Initial click to hopper at [" outX ", " outY "]")
                ctx.failsafe.ResetPhaseTimer(ctx)
            }
        }

        return "clearYellow"
    }
}

; ============================================================
; WithdrawSackPhase - clicks a fixed point to run to the ore
; sack, then waits for the inventory to receive items (slot 2 OR
; slot 12, since a gem can land in either) before moving on.
;
; Exit: if the wait exceeds sackWaitTimeoutMs, logs and stops the
; engine cleanly rather than looping or re-clicking forever.
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
        ; No TargetLock here - scratch timestamps are reset by MinePhase
        ; on the mine->clearRed transition.
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

            ctx.clicker.ClickSettled(ctx, this._sackX, this._sackY, this._runMode)
            ctx.Set("sackLastClickTime", A_TickCount)
            ctx.Log("WithdrawSackPhase: Clicked sack at [" this._sackX ", " this._sackY "]")
            ctx.failsafe.ResetPhaseTimer(ctx)
        }

        return "withdrawSack"
    }
}

; ============================================================
; DepositBankPhase - finds and clicks the deposit container (a
; magenta 0xFF00FF marker), waits for the deposit box's "Deposit
; All" button image to appear, then clicks it.
;
; Exit: once deposited, transitions to returnMine1. Stops the
; engine cleanly if the deposit box image never appears.
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
        ; bankPreDelayApplied is reset by MinePhase's mine->clearRed
        ; transition, alongside the other per-cycle scratch state.
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "depositBank"

        ; One-time settle delay BEFORE searching, not after - searching
        ; first and sleeping afterward would click stale coordinates
        ; once the character/camera has kept moving during the sleep.
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
        ctx.clicker.ClickSettled(ctx, cx, cy, this._runMode)
        ctx.failsafe.ResetPhaseTimer(ctx)

        ctx.Log("DepositBankPhase: Waiting for deposit box to open...")
        if (!this._depositAnchor.WaitFor(ctx.waiter, ctx.timing, this._imagePollKey, this._imageWaitTimeoutMs, &dx, &dy)) {
            ctx.Log("DepositBankPhase: Timed out waiting for deposit box - stopping")
            ctx.engine.Stop("Timed out waiting for deposit box")
            return "depositBank"
        }

        ctx.clicker.ClickSettled(ctx, dx, dy, this._runMode)
        ctx.Log("DepositBankPhase: Deposited all - banking complete, returning to mine")
        return "returnMine1"
    }
}

; ============================================================
; ReturnMine1Phase - step 1 of walking from the bank back to the
; mine. Clicks a fixed point once, waits for an orange marker to
; appear near a calibrated point, with a re-click failsafe.
;
; Exit: transitions to returnMine2 once the marker is found.
; Stops the engine cleanly if it never appears.
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
        ; Scratch timestamps are reset by ReturnMine2Phase's stage-2
        ; full-cycle reset, alongside every other phase's state.
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
            ; Settle delay before handing off, or returnMine2 would
            ; click the step-2 waypoint instantly on its first tick.
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
            ctx.clicker.ClickSettled(ctx, this._clickX, this._clickY, this._runMode)
            ctx.Set("return1LastClickTime", A_TickCount)
            ctx.Log("ReturnMine1Phase: Clicked waypoint 1 at [" this._clickX ", " this._clickY "]")
            ctx.failsafe.ResetPhaseTimer(ctx)
        }

        return "returnMine1"
    }
}

; ============================================================
; ReturnMine2Phase - step 2 (walk + marker wait) and the final
; approach click, a 2-stage internal state machine under one
; phase name.
;
; Stage 1: click the step-2 point, wait for its marker.
; Stage 2: click the final mine-spot point, wait a fixed delay,
; then fully reset per-cycle state and hand off to "mine" -
; completing the whole loop.
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
        ; return2Stage/return2LastClickTime/return2WaitStartedAt are
        ; reset by this phase's own stage-2 completion below.
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "returnMine2"

        stage := ctx.Get("return2Stage", 1)
        if (stage == 1)
            return this._Stage1(ctx)
        return this._Stage2(ctx)
    }

    ; Stage 1: click the step-2 waypoint, wait for its marker.
    _Stage1(ctx) {
        rx1 := Max(0, this._markerX - this._searchPaddingPx)
        ry1 := Max(0, this._markerY - this._searchPaddingPx)
        rx2 := Min(A_ScreenWidth, this._markerX + this._searchPaddingPx)
        ry2 := Min(A_ScreenHeight, this._markerY + this._searchPaddingPx)

        found := ColorSearch.FindFilledBlock(rx1, ry1, rx2, ry2,
            this._markerColor, this._markerTolerance, this._markerW, this._markerH, &cx, &cy)

        if (found) {
            ctx.Log("ReturnMine2Phase: Saw waypoint 2 marker. Moving to final approach.")
            ; Settle delay before advancing, or stage 2 would fire the
            ; final approach click instantly on the next tick.
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
            ctx.clicker.ClickSettled(ctx, this._clickX, this._clickY, this._runMode)
            ctx.Set("return2LastClickTime", A_TickCount)
            ctx.Log("ReturnMine2Phase: Clicked waypoint 2 at [" this._clickX ", " this._clickY "]")
            ctx.failsafe.ResetPhaseTimer(ctx)
        }

        return "returnMine2"
    }

    ; Stage 2: click the final mine-spot point once, wait
    ; afterClickWaitMs, then fully reset and hand off to "mine".
    _Stage2(ctx) {
        lastClick := ctx.Get("return2LastClickTime", 0)
        if (lastClick == 0) {
            ctx.clicker.ClickSettled(ctx, this._finalClickX, this._finalClickY, this._runMode)
            ctx.Set("return2LastClickTime", A_TickCount)
            ctx.Log("ReturnMine2Phase: Clicked final approach spot at [" this._finalClickX ", " this._finalClickY "]")
            ctx.failsafe.ResetPhaseTimer(ctx)
            return "returnMine2"
        }

        if ((A_TickCount - lastClick) < this._afterClickWaitMs)
            return "returnMine2"

        ctx.Log("ReturnMine2Phase: Wait complete. Handing off to mine phase.")

        ; Full per-cycle reset before handing off to "mine" - without
        ; this, a second full cycle would resume every phase with stale
        ; state left over from the first one.
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
        ctx.Set("yellowEntryDelayApplied", false)
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

; Every .ini key this bot needs, declared up front - Config.Load()
; fails fast listing all missing keys, no silent code-side defaults.
schema := Map(
    "runnerTickMs", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutMine", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutBank", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutSack", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutReturn", Map("section", "Tunables", "type", "int"),
    "colorTolerance", Map("section", "Tunables", "type", "int"),
    "targetLockMoveTolerancePx", Map("section", "Tunables", "type", "int"),
    "mineTrackBoxRadiusPx", Map("section", "Tunables", "type", "int"),
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
    "return2PostMarkerDelay", Map("section", "Tunables", "baseMsKey", "return2PostMarkerDelayMs"),
    "yellowEntryDelay", Map("section", "Tunables", "baseMsKey", "yellowEntryDelayMs")
)

iniPath := A_ScriptDir "\..\..\Config\auto-motherlode-v2.ini"
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

; Inventory layout is a fixed property of this client window (not a
; game-state tunable), so it's a hardcoded constant, not an .ini key.
; Recalibrate directly if the window ever moves/resizes.
inventoryLayout := Map("firstX", 2099, "firstY", 801, "cols", 4, "rows", 7, "slotW", 72, "slotH", 64, "gapX", 12, "gapY", 8)
ctx.inventory := Inventory(inventoryLayout)
; Full requires BOTH indicatorSlot (28) AND secondaryIndicatorSlot (27) -
; a lone gem can sit in slot 28 without the hopper collecting it, so 28
; alone can't be trusted as "full".
indicatorGate := SlotGate(botConfig.Get("indicatorSlot"), botConfig.Get("colorTolerance"), ctx.inventory)
secondaryIndicatorGate := SlotGate(botConfig.Get("secondaryIndicatorSlot"), botConfig.Get("colorTolerance"), ctx.inventory)
fullGate := AndGate([indicatorGate, secondaryIndicatorGate])
ctx.inventory.SetFullGate(fullGate)
ctx.inventory.SetEmptyGate(NotGate(fullGate))
; "Sack gave us something" - true if EITHER of two spread-out slots is
; occupied, since a gem can land in any slot.
sackGateA := SlotGate(botConfig.Get("sackGateSlotA"), botConfig.Get("colorTolerance"), ctx.inventory)
sackGateB := SlotGate(botConfig.Get("sackGateSlotB"), botConfig.Get("colorTolerance"), ctx.inventory)
ctx.inventory.SetSackGate(OrGate([sackGateA, sackGateB]))

mineRegion := Map("x1", botConfig.Get("mineRegionX1"), "y1", botConfig.Get("mineRegionY1"), "x2", botConfig.Get("mineRegionX2"), "y2", botConfig.Get("mineRegionY2"))
veinColors := [botConfig.Get("veinColorLight"), botConfig.Get("veinColorDark")]
referencePoint := Map("x", botConfig.Get("referencePointX"), "y", botConfig.Get("referencePointY"))

botClearRedPhase := ClearRedPhase(
    botConfig.Get("redColor"), botConfig.Get("redTolerance"),
    botConfig.Get("redBlockW"), botConfig.Get("redBlockH"),
    botConfig.Get("redTrackBoxRadiusPx"), botConfig.Get("redStableTicks"),
    botConfig.Get("redClearCooldownMs"), botConfig.Get("targetLockMoveTolerancePx"), botConfig.Get("runMode")
)

botClearYellowPhase := ClearYellowPhase(
    botConfig.Get("yellowColor"), botConfig.Get("yellowTolerance"),
    botConfig.Get("yellowBlockW"), botConfig.Get("yellowBlockH"),
    botConfig.Get("yellowStableTicks"), botConfig.Get("yellowClickCooldownMs"),
    "yellowEntryDelay", botConfig.Get("targetLockMoveTolerancePx"), botConfig.Get("runMode")
)

botWithdrawSackPhase := WithdrawSackPhase(
    botConfig.Get("sackRunX"), botConfig.Get("sackRunY"),
    "sackPreClickDelay", botConfig.Get("sackReclickCooldownMs"),
    botConfig.Get("sackWaitTimeoutMs"), botConfig.Get("runMode")
)

; Deposit box "Deposit All" button image anchor - the search region is
; the calibrated anchor padded by bankImageSearchPaddingPx.
; deposit-motherlode.png is 80x72px (confirmed on disk).
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
    botConfig.Get("mineTrackBoxRadiusPx"),
    botConfig.Get("mineStableTicks"),
    botConfig.Get("targetLockMoveTolerancePx"),
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
