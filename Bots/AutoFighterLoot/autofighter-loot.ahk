; ============================================================
; autofighter-loot.ahk
; AutoFighter + a post-kill loot pickup step. Combat detection
; (ScanAndAttackPhase/WaitCombatPhase) is shared with
; Bots/AutoFighter/autofighter.ahk via Core/SharedPhases.ahk - this bot
; passes "lootPickup" as WaitCombatPhase's killNextPhaseName instead of
; the default "scanAndAttack".
;
; Isolation: reads/writes only this bot's own Config/ and logs/ - never
; Bots/AutoFighter's config or log file.
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
#Include ..\..\Core\SharedPhases.ahk
#Include ..\..\Timing\Waiter.ahk
#Include ..\..\Detection\ColorSearch.ahk
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
; LootPickupPhase - after a kill, right-click the dropped bb-item,
; click the take-bb menu option, then click inventory slot 1.
;
; Staged internally under one phase name (mirrors Motherlode's
; ReturnMine2Phase 2-stage pattern):
;   0: one-time settle delay before searching at all.
;   1: find+right-click bb-item.png.
;   2: find+left-click take-bb.png (the menu option itself).
;   3: one-time settle delay, then click inventory slot 1.
;
; Deliberate exception to this codebase's usual timeout convention:
; every kill is expected to drop this item, but if stage 1 or stage 2's
; search times out anyway, this phase does NOT call ctx.engine.Stop -
; it logs the miss and returns to scanAndAttack, keeping the bot
; running rather than treating a single missed loot pickup as fatal.
; ============================================================
class LootPickupPhase extends Phase {
    __New(preSearchDelayKey, bbItemAnchor, bbItemPollKey, bbItemWaitTimeoutMs, takeBbAnchor, takeBbPollKey, takeBbWaitTimeoutMs, postTakeDelayKey, inventory, runMode := false) {
        super.__New("lootPickup")
        this._preSearchDelayKey := preSearchDelayKey
        this._bbItemAnchor := bbItemAnchor
        this._bbItemPollKey := bbItemPollKey
        this._bbItemWaitTimeoutMs := bbItemWaitTimeoutMs
        this._takeBbAnchor := takeBbAnchor
        this._takeBbPollKey := takeBbPollKey
        this._takeBbWaitTimeoutMs := takeBbWaitTimeoutMs
        this._postTakeDelayKey := postTakeDelayKey
        this._inventory := inventory
        this._runMode := runMode
    }

    ResetForNewCycle() {
        ; lootStage/lootWaitStartedAt are reset by this phase's own exit
        ; paths below (both the success path and the timeout-skip paths).
    }

    _ResetAndReturnToScan(ctx) {
        ctx.Set("lootStage", 0)
        ctx.Set("lootPreDelayApplied", false)
        ctx.Set("lootWaitStartedAt", 0)
        return "scanAndAttack"
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "lootPickup"

        stage := ctx.Get("lootStage", 0)

        if (stage == 0) {
            if (!ctx.Get("lootPreDelayApplied", false)) {
                ctx.waiter.After(ctx.timing, this._preSearchDelayKey)
                ctx.Set("lootPreDelayApplied", true)
            }
            ctx.Set("lootStage", 1)
            ctx.Set("lootWaitStartedAt", 0)
            ctx.failsafe.ResetPhaseTimer(ctx)
            return "lootPickup"
        }

        if (stage == 1) {
            if (this._bbItemAnchor.Find(&ix, &iy)) {
                ctx.Log("LootPickupPhase: Found bb-item at [" ix ", " iy "]. Right-clicking.")
                ; Never Ctrl-hold a right-click: runMode's Ctrl-hold is
                ; OSRS's left-click "force-run"/quick-action modifier
                ; everywhere else it's used in this codebase - holding
                ; Ctrl during a right-click (which opens a context menu)
                ; is untested/unestablished behavior and risks silently
                ; altering or suppressing the menu this phase depends on.
                ctx.clicker.ClickSettled(ctx, ix, iy, false, "Right")
                ctx.Set("lootStage", 2)
                ctx.Set("lootWaitStartedAt", 0)
                ctx.failsafe.ResetPhaseTimer(ctx)
                return "lootPickup"
            }

            waitStartedAt := ctx.Get("lootWaitStartedAt", 0)
            if (waitStartedAt == 0) {
                ctx.Set("lootWaitStartedAt", A_TickCount)
            } else if ((A_TickCount - waitStartedAt) > this._bbItemWaitTimeoutMs) {
                ctx.Log("LootPickupPhase: bb-item.png not found in time (unexpected - every kill should drop it). Skipping loot, resuming scan.")
                return this._ResetAndReturnToScan(ctx)
            }
            ctx.waiter.After(ctx.timing, this._bbItemPollKey)
            return "lootPickup"
        }

        if (stage == 2) {
            if (this._takeBbAnchor.Find(&tx, &ty)) {
                ctx.Log("LootPickupPhase: Found take-bb at [" tx ", " ty "]. Clicking.")
                ctx.clicker.ClickSettled(ctx, tx, ty, this._runMode)
                ctx.Set("lootStage", 3)
                ctx.Set("lootWaitStartedAt", 0)
                ctx.failsafe.ResetPhaseTimer(ctx)
                return "lootPickup"
            }

            waitStartedAt := ctx.Get("lootWaitStartedAt", 0)
            if (waitStartedAt == 0) {
                ctx.Set("lootWaitStartedAt", A_TickCount)
            } else if ((A_TickCount - waitStartedAt) > this._takeBbWaitTimeoutMs) {
                ctx.Log("LootPickupPhase: take-bb.png not found in time (unexpected). Skipping loot, resuming scan.")
                return this._ResetAndReturnToScan(ctx)
            }
            ctx.waiter.After(ctx.timing, this._takeBbPollKey)
            return "lootPickup"
        }

        ; stage 3: settle, then click inventory slot 1.
        ctx.waiter.After(ctx.timing, this._postTakeDelayKey)
        this._inventory.SlotCenter(1, &slotX, &slotY)
        ctx.Log("LootPickupPhase: Clicking inventory slot 1 at [" slotX ", " slotY "].")
        ctx.clicker.ClickSettled(ctx, slotX, slotY, this._runMode)
        return this._ResetAndReturnToScan(ctx)
    }
}

; ============================================================
; Wiring
; ============================================================

schema := Map(
    "runnerTickMs", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutScan", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutCombat", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutLoot", Map("section", "Tunables", "type", "int"),
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
    "postKillLootDelayMs", Map("section", "Tunables", "type", "int"),
    "lootSearchCenterX", Map("section", "Tunables", "type", "int"),
    "lootSearchCenterY", Map("section", "Tunables", "type", "int"),
    "lootSearchWidth", Map("section", "Tunables", "type", "int"),
    "lootSearchHeight", Map("section", "Tunables", "type", "int"),
    "bbItemPollMs", Map("section", "Tunables", "type", "int"),
    "bbItemWaitTimeoutMs", Map("section", "Tunables", "type", "int"),
    "takeBbPollMs", Map("section", "Tunables", "type", "int"),
    "takeBbWaitTimeoutMs", Map("section", "Tunables", "type", "int"),
    "postTakeDelayMs", Map("section", "Tunables", "type", "int"),
    "clickSettleMs", Map("section", "Tunables", "type", "int"),
    "clickSettleJitterPercent", Map("section", "Tunables", "type", "int"),
    "ctrlHoldSettleMs", Map("section", "Tunables", "type", "int"),
    "runMode", Map("section", "Settings", "type", "int")
)
timingSchema := Map(
    "clickSettle", Map("section", "Tunables", "baseMsKey", "clickSettleMs", "jitterPercentKey", "clickSettleJitterPercent"),
    "ctrlHoldSettle", Map("section", "Tunables", "baseMsKey", "ctrlHoldSettleMs", "jitterPercentKey", "clickSettleJitterPercent"),
    "postKillSettle", Map("section", "Tunables", "baseMsKey", "postKillSettleDelayMs"),
    "scanPoll", Map("section", "Tunables", "baseMsKey", "scanPollMs"),
    "combatPoll", Map("section", "Tunables", "baseMsKey", "combatPollMs"),
    "postKillLootDelay", Map("section", "Tunables", "baseMsKey", "postKillLootDelayMs"),
    "bbItemPoll", Map("section", "Tunables", "baseMsKey", "bbItemPollMs"),
    "takeBbPoll", Map("section", "Tunables", "baseMsKey", "takeBbPollMs"),
    "postTakeDelay", Map("section", "Tunables", "baseMsKey", "postTakeDelayMs")
)

iniPath := A_ScriptDir "\..\..\Config\auto-fighter-loot.ini"
botConfig := Config(iniPath, schema, timingSchema)
botConfig.Load()

botLogger := Logger(A_ScriptDir "\..\..\logs\auto-fighter-loot-v4-debug.log")
botHumanizer := Humanizer(false)
botClicker := Clicker(botHumanizer)
botFailsafe := FailSafe(botLogger)
botWaiter := Waiter((baseMs, jitterPercent) => botHumanizer.Jitter(baseMs, jitterPercent))
botWindowFocus := WindowFocus()
botOverlay := Overlay(8, 10, 10)

ctx := EngineContext(botConfig, botLogger, botClicker, botFailsafe, botWaiter, botWindowFocus, botOverlay)

; Inventory layout is a fixed property of this client window (not a
; game-state tunable) - same values as every other bot on this client.
; Only used here for SlotCenter(1, ...) - no full/empty gate needed.
inventoryLayout := Map("firstX", 2099, "firstY", 801, "cols", 4, "rows", 7, "slotW", 72, "slotH", 64, "gapX", 12, "gapY", 8)
ctx.inventory := Inventory(inventoryLayout)

combatIndicatorGate := PixelColorGate(
    botConfig.Get("combatIndicatorX"), botConfig.Get("combatIndicatorY"), botConfig.Get("combatIndicatorTolerance")
)

botScanAndAttackPhase := ScanAndAttackPhase(
    botConfig.Get("targetColor"), botConfig.Get("targetColorTolerance"),
    botConfig.Get("refPointX"), botConfig.Get("refPointY"),
    botConfig.Get("targetSearchRadiusX"), botConfig.Get("targetSearchRadiusY"),
    botConfig.Get("targetBlobRadius"), botConfig.Get("targetSampleRate"), botConfig.Get("targetSeedRowStep"), "scanPoll",
    botConfig.Get("targetWaitTimeoutMs"), "waitCombat", botConfig.Get("runMode")
)

botWaitCombatPhase := WaitCombatPhase(
    combatIndicatorGate, botConfig.Get("combatStartColor"), botConfig.Get("combatKillColor"),
    "combatPoll", botConfig.Get("retryClickAfterMs"), botConfig.Get("combatStartTimeoutMs"), "postKillSettle", "lootPickup"
)

; bb-item.png uses #00FF00 as its transparent-background marker color -
; ImageSearch is told to ignore that color via *Trans0x00FF00, or it
; would try to match those pixels literally against the real (non-green)
; game background.
lootRegion := Map(
    "x1", botConfig.Get("lootSearchCenterX") - botConfig.Get("lootSearchWidth") // 2,
    "y1", botConfig.Get("lootSearchCenterY") - botConfig.Get("lootSearchHeight") // 2,
    "x2", botConfig.Get("lootSearchCenterX") + botConfig.Get("lootSearchWidth") // 2,
    "y2", botConfig.Get("lootSearchCenterY") + botConfig.Get("lootSearchHeight") // 2
)
bbItemImagePath := A_ScriptDir "\..\..\Images\bb-item.png"
bbItemAnchor := ImageAnchor(lootRegion, bbItemImagePath, 94, 22, "*Trans0x00FF00")

takeBbImagePath := A_ScriptDir "\..\..\Images\take-bb.png"
takeBbAnchor := ImageAnchor(lootRegion, takeBbImagePath, 194, 30)

botLootPickupPhase := LootPickupPhase(
    "postKillLootDelay",
    bbItemAnchor, "bbItemPoll", botConfig.Get("bbItemWaitTimeoutMs"),
    takeBbAnchor, "takeBbPoll", botConfig.Get("takeBbWaitTimeoutMs"),
    "postTakeDelay", ctx.inventory, botConfig.Get("runMode")
)

botEngine := Engine(ctx, botConfig.Get("runnerTickMs"))
ctx.engine := botEngine
botEngine.AddPhase(botScanAndAttackPhase, botConfig.Get("phaseTimeoutScan"))
botEngine.AddPhase(botWaitCombatPhase, botConfig.Get("phaseTimeoutCombat"))
botEngine.AddPhase(botLootPickupPhase, botConfig.Get("phaseTimeoutLoot"))

F5:: botEngine.Start("scanAndAttack")
F6:: {
    botEngine.Stop("Stopped (F6)")
    botOverlay.Clear()
}
