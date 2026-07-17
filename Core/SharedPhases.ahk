; ============================================================
; SharedPhases.ahk
; Generic Phase classes reused across bots wherever their shape
; is identical apart from names/keys - not framework primitives
; (those stay in Phase.ahk), but not bot-specific either.
; ============================================================

#Requires AutoHotkey v2.0

#Include Phase.ahk
#Include ..\Detection\ColorSearch.ahk

; ============================================================
; PressAndWaitEmptyPhase - presses a key once to confirm a
; dialog, then waits (the game runs the action on its own) until
; the inventory empties. Used by Firemaking's "burn logs" and
; Smelter's "smelt ore" - identical shape, different key/dialog.
;
; Exit: once inventory is empty, transitions to nextPhaseName.
; ============================================================
class PressAndWaitEmptyPhase extends Phase {
    __New(name, keyAction, key, spaceSettleKey, nextPhaseName) {
        super.__New(name)
        this._keyAction := keyAction
        this._key := key
        this._spaceSettleKey := spaceSettleKey
        this._nextPhaseName := nextPhaseName
    }

    ResetForNewCycle() {
        ; keyPressed is reset by the withdraw phase's per-cycle reset.
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return this.name

        if (!ctx.Get("keyPressed", false)) {
            this._keyAction.Press(this._key)
            ctx.waiter.After(ctx.timing, this._spaceSettleKey)
            ctx.Set("keyPressed", true)
            ctx.Log(this.name ": Pressed " this._key " to confirm dialog")
            ctx.failsafe.ResetPhaseTimer(ctx)
            return this.name
        }

        if (ctx.inventory.IsEmpty()) {
            ctx.Log(this.name ": Inventory empty. Moving to bank.")
            return this._nextPhaseName
        }

        return this.name
    }
}

; ============================================================
; GoToBankPhase - verifies a fixed-point color marker, clicks
; it, then waits for a bank-open image to appear. Used by
; Firemaking (a pure detection signal, never clicked further)
; and Smelter (the same image is then clicked as deposit-all by
; the phase after this one) - identical up to this point.
;
; Exit: once the bank-open image is found, transitions to
; nextPhaseName.
; ============================================================
class GoToBankPhase extends Phase {
    __New(markerX, markerY, markerW, markerH, markerColor, markerTolerance, searchPaddingPx, reclickCooldownMs, markerWaitTimeoutMs, bankOpenAnchor, bankOpenWaitTimeoutMs, bankOpenPollKey, nextPhaseName, runMode := false) {
        super.__New("goToBank")
        this._markerX := markerX
        this._markerY := markerY
        this._markerW := markerW
        this._markerH := markerH
        this._markerColor := markerColor
        this._markerTolerance := markerTolerance
        this._searchPaddingPx := searchPaddingPx
        this._reclickCooldownMs := reclickCooldownMs
        this._markerWaitTimeoutMs := markerWaitTimeoutMs
        this._bankOpenAnchor := bankOpenAnchor
        this._bankOpenWaitTimeoutMs := bankOpenWaitTimeoutMs
        this._bankOpenPollKey := bankOpenPollKey
        this._nextPhaseName := nextPhaseName
        this._runMode := runMode
    }

    ResetForNewCycle() {
        ; Scratch timestamps are reset by the withdraw phase's per-cycle
        ; reset.
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "goToBank"

        if (!ctx.Get("bankMarkerClicked", false)) {
            rx1 := Max(0, this._markerX - this._searchPaddingPx)
            ry1 := Max(0, this._markerY - this._searchPaddingPx)
            rx2 := Min(A_ScreenWidth, this._markerX + this._searchPaddingPx)
            ry2 := Min(A_ScreenHeight, this._markerY + this._searchPaddingPx)

            found := ColorSearch.FindFilledBlock(rx1, ry1, rx2, ry2,
                this._markerColor, this._markerTolerance, this._markerW, this._markerH, &cx, &cy,
                false, this._markerX, this._markerY)

            if (!found) {
                waitStartedAt := ctx.Get("bankMarkerWaitStartedAt", 0)
                if (waitStartedAt == 0) {
                    ctx.Set("bankMarkerWaitStartedAt", A_TickCount)
                } else if ((A_TickCount - waitStartedAt) > this._markerWaitTimeoutMs) {
                    ctx.Log("GoToBankPhase: Timed out waiting for the bank marker - stopping")
                    ctx.engine.Stop("Timed out waiting for bank marker")
                    return "goToBank"
                }

                lastClick := ctx.Get("bankMarkerLastClickTime", 0)
                if (lastClick == 0 || (A_TickCount - lastClick) > this._reclickCooldownMs) {
                    ctx.clicker.ClickSettled(ctx, this._markerX, this._markerY, this._runMode)
                    ctx.Set("bankMarkerLastClickTime", A_TickCount)
                    ctx.Log("GoToBankPhase: Clicked bank marker at [" this._markerX ", " this._markerY "]")
                    ctx.failsafe.ResetPhaseTimer(ctx)
                }
                return "goToBank"
            }

            ctx.Log("GoToBankPhase: Found bank marker at [" cx ", " cy "]")
            ctx.clicker.ClickSettled(ctx, cx, cy, this._runMode)
            ctx.Set("bankMarkerClicked", true)
            ctx.failsafe.ResetPhaseTimer(ctx)
        }

        ctx.Log("GoToBankPhase: Waiting for bank interface...")
        if (!this._bankOpenAnchor.WaitFor(ctx.waiter, ctx.timing, this._bankOpenPollKey, this._bankOpenWaitTimeoutMs, &dx, &dy)) {
            ctx.Log("GoToBankPhase: Timed out waiting for bank interface - stopping")
            ctx.engine.Stop("Timed out waiting for bank interface")
            return "goToBank"
        }

        ctx.Log("GoToBankPhase: Bank interface open.")
        return this._nextPhaseName
    }
}

; ============================================================
; ScanAndAttackPhase - scans a bounded box around the reference point
; for the nearest irregular color blob (e.g. an NPC overlay), clicks
; its centroid, then hands off to nextPhaseName. Shared by AutoFighter
; and AutoFighterLoot - identical shape, only the phase to hand off to
; after a click ever differs.
;
; Scoped to searchRadiusX/Y around (refX, refY) instead of the whole
; screen - "nearest to ref" rarely picks a faraway match anyway, and a
; smaller region means far fewer PixelSearch calls for the same
; rowStep, buying back precision (a finer seedRowStep/sampleRate)
; without paying the full-screen scan's latency cost.
;
; Exit: once clicked, transitions to nextPhaseName. Stops the engine
; cleanly if no target blob appears within targetWaitTimeoutMs.
; ============================================================
class ScanAndAttackPhase extends Phase {
    __New(targetColor, targetTolerance, refX, refY, searchRadiusX, searchRadiusY, blobRadius, sampleRate, seedRowStep, scanPollKey, waitTimeoutMs, nextPhaseName, runMode := false) {
        super.__New("scanAndAttack")
        this._targetColor := targetColor
        this._targetTolerance := targetTolerance
        this._refX := refX
        this._refY := refY
        this._searchRadiusX := searchRadiusX
        this._searchRadiusY := searchRadiusY
        this._blobRadius := blobRadius
        this._sampleRate := sampleRate
        this._seedRowStep := seedRowStep
        this._scanPollKey := scanPollKey
        this._waitTimeoutMs := waitTimeoutMs
        this._nextPhaseName := nextPhaseName
        this._runMode := runMode
    }

    ResetForNewCycle() {
        ; targetWaitStartedAt is reset by WaitCombatPhase's own completion.
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "scanAndAttack"

        x1 := Max(0, this._refX - this._searchRadiusX)
        y1 := Max(0, this._refY - this._searchRadiusY)
        x2 := Min(A_ScreenWidth, this._refX + this._searchRadiusX)
        y2 := Min(A_ScreenHeight, this._refY + this._searchRadiusY)

        found := ColorSearch.FindNearestBlobCenter(x1, y1, x2, y2,
            this._refX, this._refY, this._targetColor, this._targetTolerance,
            this._blobRadius, &tx, &ty, this._sampleRate, this._seedRowStep)

        if (!found) {
            waitStartedAt := ctx.Get("targetWaitStartedAt", 0)
            if (waitStartedAt == 0) {
                ctx.Set("targetWaitStartedAt", A_TickCount)
            } else if ((A_TickCount - waitStartedAt) > this._waitTimeoutMs) {
                ctx.Log("ScanAndAttackPhase: Timed out waiting for a target - stopping")
                ctx.engine.Stop("Timed out waiting for a target")
                return "scanAndAttack"
            }
            ctx.waiter.After(ctx.timing, this._scanPollKey)
            return "scanAndAttack"
        }

        ctx.Set("targetWaitStartedAt", 0)
        ctx.Log("ScanAndAttackPhase: Found target blob at [" tx ", " ty "]")
        ctx.clicker.ClickSettled(ctx, tx, ty, this._runMode)
        ctx.failsafe.ResetPhaseTimer(ctx)

        ; Fresh per-click baseline for WaitCombatPhase's stale-killColor
        ; guard - every new click (including a retry after a stall) needs
        ; its own snapshot of whether killColor was already showing before
        ; THIS fight had any chance to happen.
        ctx.Set("entrySnapshotTaken", false)
        ctx.Set("combatWaitStartedAt", 0)

        return this._nextPhaseName
    }
}

; ============================================================
; WaitCombatPhase - polls the 1x1 combat-indicator pixel. Green
; means "fighting, not dead yet" (keep waiting); dark red means
; "kill confirmed" (settle, then hand off to killNextPhaseName - e.g.
; back to scanning for AutoFighter, or on to a loot-pickup phase for
; AutoFighterLoot). If neither color has appeared within
; retryClickAfterMs of the attack click, the click likely missed the
; (moving/irregular) blob - go back to scanAndAttack and try again
; rather than waiting out the full combatStartTimeoutMs. Only if that
; retry cycle itself keeps failing for combatStartTimeoutMs total does
; it stop cleanly.
;
; Gotcha fixed here: the kill-color indicator was measured (live) to
; stay on screen for ~3s AFTER a kill (death animation), which
; outlasts postKillSettleDelayMs - without a guard, the very next
; click's waitCombat tick would immediately re-read that STALE kill
; color as "new kill confirmed" before the new fight ever started,
; producing a rapid false-kill loop.
;
; Fix (was: require startColor seen first - wrong, since a genuine
; one-shot kill can go straight to killColor with startColor never
; appearing at all, which made real instant kills wait out the full
; retryClickAfterMs instead of being recognized immediately). The
; real distinction is STALE (killColor already present at the moment
; this phase was entered, i.e. leftover from the previous kill) vs.
; FRESH (killColor appearing after having NOT been present at entry -
; whether or not startColor was ever seen in between). wasKillColorAtEntry
; is captured once on entry and only killColor readings after that
; baseline clears count as a fresh kill.
; ============================================================
class WaitCombatPhase extends Phase {
    __New(indicatorGate, startColor, killColor, combatPollKey, retryClickAfterMs, startTimeoutMs, postKillSettleKey, killNextPhaseName := "scanAndAttack", retryNextPhaseName := "") {
        super.__New("waitCombat")
        this._indicatorGate := indicatorGate
        this._startColor := startColor
        this._killColor := killColor
        this._combatPollKey := combatPollKey
        this._retryClickAfterMs := retryClickAfterMs
        this._startTimeoutMs := startTimeoutMs
        this._postKillSettleKey := postKillSettleKey
        this._killNextPhaseName := killNextPhaseName
        ; Where to go when no combat signal shows up in time (a missed/
        ; no-op click, or - for a passive-aggro bot with no attack click at
        ; all - simply nothing happening yet). Defaults to killNextPhaseName
        ; itself: for AutoFighter/AutoFighterLoot this is "scanAndAttack"
        ; (the same phase either way, so the old hardcoded value is
        ; preserved); a bot with a different re-entry point (e.g.
        ; FruitStall's "thieving") should pass its own.
        this._retryNextPhaseName := retryNextPhaseName != "" ? retryNextPhaseName : killNextPhaseName
    }

    ResetForNewCycle() {
        ; combatWaitStartedAt/staleKillCleared reset below on kill.
    }

    Run(ctx) {
        ; Captured once, the first tick this phase runs after a click -
        ; establishes whether killColor was already showing (stale, from the
        ; previous kill's lingering death animation) before this fight had
        ; any chance to actually happen.
        if (!ctx.Get("entrySnapshotTaken", false)) {
            ctx.Set("entrySnapshotTaken", true)
            ctx.Set("staleKillCleared", !this._indicatorGate.Matches(this._killColor))
        }

        if (!ctx.Get("staleKillCleared", false)) {
            ; Stale killColor hasn't cleared yet - only a REAL state change
            ; (no longer killColor) proves the previous fight's residue is
            ; gone and this fight's own signal can now be trusted.
            if (!this._indicatorGate.Matches(this._killColor))
                ctx.Set("staleKillCleared", true)
        } else if (this._indicatorGate.Matches(this._killColor)) {
            ctx.Log("WaitCombatPhase: Kill confirmed. Settling before next phase.")
            ctx.waiter.After(ctx.timing, this._postKillSettleKey)
            ctx.Set("targetWaitStartedAt", 0)
            ctx.Set("combatWaitStartedAt", 0)
            ctx.Set("entrySnapshotTaken", false)
            ctx.Set("staleKillCleared", false)
            ctx.Set("combatStartLogged", false)
            ctx.failsafe.ResetPhaseTimer(ctx)
            return this._killNextPhaseName
        }

        if (this._indicatorGate.Matches(this._startColor)) {
            ; Logged once per fight via its own latch - independent of
            ; combatWaitStartedAt, which only tracks the no-signal-yet
            ; timeout and is already 0 (never armed) when startColor shows
            ; up on the very first tick, which would otherwise skip this
            ; log entirely.
            if (!ctx.Get("combatStartLogged", false)) {
                ctx.Log("WaitCombatPhase: Combat started. Waiting for kill.")
                ctx.Set("combatStartLogged", true)
            }
            ; Reset on EVERY tick combat is confirmed ongoing, not just the
            ; first - startColor still matching is proof this phase is
            ; making real progress (fighting), not stalled, so a long fight
            ; must not trip phaseTimeoutCombat just because it outlasts that
            ; budget.
            ctx.failsafe.ResetPhaseTimer(ctx)
            ctx.Set("combatWaitStartedAt", 0)
            ctx.waiter.After(ctx.timing, this._combatPollKey)
            return "waitCombat"
        }

        ; Neither a fresh kill nor combat-start observed yet - only relevant
        ; if this drags on past the attack click with no combat signal at
        ; all (a miss/no-op click, or stale killColor still lingering).
        waitStartedAt := ctx.Get("combatWaitStartedAt", 0)
        if (waitStartedAt == 0) {
            ctx.Set("combatWaitStartedAt", A_TickCount)
        } else if ((A_TickCount - waitStartedAt) > this._startTimeoutMs) {
            ctx.Log("WaitCombatPhase: Timed out waiting for a combat signal - stopping")
            ctx.engine.Stop("Timed out waiting for combat signal")
            return "waitCombat"
        } else if ((A_TickCount - waitStartedAt) > this._retryClickAfterMs) {
            ctx.Log("WaitCombatPhase: No combat signal after " this._retryClickAfterMs "ms - retrying")
            ctx.Set("combatWaitStartedAt", 0)
            ctx.Set("entrySnapshotTaken", false)
            ctx.Set("staleKillCleared", false)
            ctx.Set("combatStartLogged", false)
            ctx.failsafe.ResetPhaseTimer(ctx)
            return this._retryNextPhaseName
        }

        ctx.waiter.After(ctx.timing, this._combatPollKey)
        return "waitCombat"
    }
}
