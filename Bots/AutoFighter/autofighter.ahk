; ============================================================
; autofighter.ahk
; v4 entry point + all Auto Fighter phases, one file (single
; bot/single loop, same shape as the other bots).
;
; Unlike every other v4 bot, this one has no bank/inventory step -
; it's a pure scan -> click -> wait-for-combat-signal -> repeat loop
; against a whole-viewport scan for irregular NPC-overlay blobs
; (#FF00FF), since OSRS paints those as variably-shaped/sized
; outlines, not a fixed solid block.
;
; Isolation: reads/writes only v4's own config/ and logs/ - never
; the legacy repo-root config/ or logs/ folders.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

#Include ..\..\Core\Engine.ahk
#Include ..\..\Core\EngineContext.ahk
#Include ..\..\Core\FailSafe.ahk
#Include ..\..\Core\Phase.ahk
#Include ..\..\Timing\Waiter.ahk
#Include ..\..\Detection\ColorSearch.ahk
#Include ..\..\Detection\Telemetry.ahk
#Include ..\..\Actions\Humanizer.ahk
#Include ..\..\Actions\Click.ahk
#Include ..\..\Config\Config.ahk
#Include ..\..\Diagnostics\Logger.ahk
#Include ..\..\Diagnostics\WindowFocus.ahk
#Include ..\..\Diagnostics\Overlay.ahk

; ============================================================
; ScanAndAttackPhase - scans a bounded box around the reference point
; for the nearest #FF00FF NPC blob, clicks its centroid, then hands
; off to waitCombat.
;
; Scoped to searchRadiusX/Y around (refX, refY) instead of the whole
; screen - "nearest to ref" rarely picks a faraway match anyway, and a
; smaller region means far fewer PixelSearch calls for the same
; rowStep, buying back precision (a finer seedRowStep/sampleRate)
; without paying the full-screen scan's latency cost.
;
; Exit: once clicked, transitions to waitCombat. Stops the engine
; cleanly if no target blob appears within targetWaitTimeoutMs.
; ============================================================
class ScanAndAttackPhase extends Phase {
    __New(targetColor, targetTolerance, refX, refY, searchRadiusX, searchRadiusY, blobRadius, sampleRate, seedRowStep, scanPollKey, waitTimeoutMs, runMode := false) {
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

        return "waitCombat"
    }
}

; ============================================================
; WaitCombatPhase - polls the 1x1 combat-indicator pixel. Green
; means "fighting, not dead yet" (keep waiting); dark red means
; "kill confirmed" (settle, then rescan). If neither color has
; appeared within retryClickAfterMs of the attack click, the click
; likely missed the (moving/irregular) blob - go back to
; scanAndAttack and try again rather than waiting out the full
; combatStartTimeoutMs. Only if that retry cycle itself keeps
; failing for combatStartTimeoutMs total does it stop cleanly.
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
    __New(indicatorGate, startColor, killColor, combatPollKey, retryClickAfterMs, startTimeoutMs, postKillSettleKey) {
        super.__New("waitCombat")
        this._indicatorGate := indicatorGate
        this._startColor := startColor
        this._killColor := killColor
        this._combatPollKey := combatPollKey
        this._retryClickAfterMs := retryClickAfterMs
        this._startTimeoutMs := startTimeoutMs
        this._postKillSettleKey := postKillSettleKey
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
            ctx.Log("WaitCombatPhase: Kill confirmed. Settling before rescan.")
            ctx.waiter.After(ctx.timing, this._postKillSettleKey)
            ctx.Set("targetWaitStartedAt", 0)
            ctx.Set("combatWaitStartedAt", 0)
            ctx.Set("entrySnapshotTaken", false)
            ctx.Set("staleKillCleared", false)
            ctx.failsafe.ResetPhaseTimer(ctx)
            return "scanAndAttack"
        }

        if (this._indicatorGate.Matches(this._startColor)) {
            if (ctx.Get("combatWaitStartedAt", 0) != 0) {
                ctx.Log("WaitCombatPhase: Combat started. Waiting for kill.")
                ctx.failsafe.ResetPhaseTimer(ctx)
            }
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
            ctx.Log("WaitCombatPhase: No combat signal after " this._retryClickAfterMs "ms - click likely missed, retrying scan")
            ctx.Set("combatWaitStartedAt", 0)
            ctx.failsafe.ResetPhaseTimer(ctx)
            return "scanAndAttack"
        }

        ctx.waiter.After(ctx.timing, this._combatPollKey)
        return "waitCombat"
    }
}

; ============================================================
; Wiring
; ============================================================

schema := Map(
    "runnerTickMs", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutScan", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutCombat", Map("section", "Tunables", "type", "int"),
    "targetColor", Map("section", "Tunables", "type", "color"),
    "targetColorTolerance", Map("section", "Tunables", "type", "int"),
    "targetBlobRadius", Map("section", "Tunables", "type", "int"),
    "targetSampleRate", Map("section", "Tunables", "type", "int"),
    "targetSeedRowStep", Map("section", "Tunables", "type", "int"),
    "refPointX", Map("section", "Tunables", "type", "int"),
    "refPointY", Map("section", "Tunables", "type", "int"),
    "targetSearchRadiusX", Map("section", "Tunables", "type", "int"),
    "targetSearchRadiusY", Map("section", "Tunables", "type", "int"),
    "scanPollMs", Map("section", "Tunables", "type", "int"),
    "targetWaitTimeoutMs", Map("section", "Tunables", "type", "int"),
    "combatIndicatorX", Map("section", "Tunables", "type", "int"),
    "combatIndicatorY", Map("section", "Tunables", "type", "int"),
    "combatIndicatorTolerance", Map("section", "Tunables", "type", "int"),
    "combatStartColor", Map("section", "Tunables", "type", "color"),
    "combatKillColor", Map("section", "Tunables", "type", "color"),
    "combatPollMs", Map("section", "Tunables", "type", "int"),
    "retryClickAfterMs", Map("section", "Tunables", "type", "int"),
    "combatStartTimeoutMs", Map("section", "Tunables", "type", "int"),
    "postKillSettleDelayMs", Map("section", "Tunables", "type", "int"),
    "runMode", Map("section", "Settings", "type", "int")
)
timingSchema := Map(
    "clickSettle", Map("section", "Tunables", "baseMsKey", "clickSettleMs", "jitterPercentKey", "clickSettleJitterPercent"),
    "ctrlHoldSettle", Map("section", "Tunables", "baseMsKey", "ctrlHoldSettleMs", "jitterPercentKey", "clickSettleJitterPercent"),
    "postKillSettle", Map("section", "Tunables", "baseMsKey", "postKillSettleDelayMs"),
    "scanPoll", Map("section", "Tunables", "baseMsKey", "scanPollMs"),
    "combatPoll", Map("section", "Tunables", "baseMsKey", "combatPollMs")
)

iniPath := A_ScriptDir "\..\..\Config\auto-fighter-v2.ini"
botConfig := Config(iniPath, schema, timingSchema)
botConfig.Load()

botLogger := Logger(A_ScriptDir "\..\..\logs\auto-fighter-v4-debug.log")
botHumanizer := Humanizer(false)
botClicker := Clicker(botHumanizer)
botFailsafe := FailSafe(botLogger)
botWaiter := Waiter((baseMs, jitterPercent) => botHumanizer.Jitter(baseMs, jitterPercent))
botWindowFocus := WindowFocus()
botOverlay := Overlay(8, 10, 10)

ctx := EngineContext(botConfig, botLogger, botClicker, botFailsafe, botWaiter, botWindowFocus, botOverlay)

combatIndicatorGate := PixelColorGate(
    botConfig.Get("combatIndicatorX"), botConfig.Get("combatIndicatorY"), botConfig.Get("combatIndicatorTolerance")
)

botScanAndAttackPhase := ScanAndAttackPhase(
    botConfig.Get("targetColor"), botConfig.Get("targetColorTolerance"),
    botConfig.Get("refPointX"), botConfig.Get("refPointY"),
    botConfig.Get("targetSearchRadiusX"), botConfig.Get("targetSearchRadiusY"),
    botConfig.Get("targetBlobRadius"), botConfig.Get("targetSampleRate"), botConfig.Get("targetSeedRowStep"), "scanPoll",
    botConfig.Get("targetWaitTimeoutMs"), botConfig.Get("runMode")
)

botWaitCombatPhase := WaitCombatPhase(
    combatIndicatorGate, botConfig.Get("combatStartColor"), botConfig.Get("combatKillColor"),
    "combatPoll", botConfig.Get("retryClickAfterMs"), botConfig.Get("combatStartTimeoutMs"), "postKillSettle"
)

botEngine := Engine(ctx, botConfig.Get("runnerTickMs"))
ctx.engine := botEngine
botEngine.AddPhase(botScanAndAttackPhase, botConfig.Get("phaseTimeoutScan"))
botEngine.AddPhase(botWaitCombatPhase, botConfig.Get("phaseTimeoutCombat"))

F5:: botEngine.Start("scanAndAttack")
F6:: {
    botEngine.Stop("Stopped (F6)")
    botOverlay.Clear()
}
