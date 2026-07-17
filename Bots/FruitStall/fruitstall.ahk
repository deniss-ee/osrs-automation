; ============================================================
; fruitstall.ahk
; v4 entry point + ThievingPhase. Two states: thieve the stall,
; or fight an NPC that came after a detected steal attempt.
;
; Loop: click the stall's #00FF00 ready-pixel, wait for inventory
; slot 1 to become occupied (the stolen fruit landing), click it,
; repeat. If slot 1 never fills within lootWaitTimeoutMs, the theft
; was detected and an aggressive NPC is inbound - hand off to
; WaitCombatPhase (the same phase AutoFighter uses) to fight it out,
; then resume thieving after a settle delay once it's dead.
;
; Reuses existing primitives unchanged - no new detection code:
; ColorSearch.IsColorAt for the stall's ready-pixel, Inventory/SlotGate
; for "is slot 1 occupied" (same mechanism as Smithing/Motherlode/
; Firemaking's indicator slots), and Core/SharedPhases.ahk's
; WaitCombatPhase for the fight (same combat-indicator pixel/colors as
; AutoFighter, since it's the same underlying game HP/combat overlay).
;
; Isolation: reads/writes only this bot's own Config/ and logs/.
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
#Include ..\..\Interfaces\Inventory.ahk
#Include ..\..\Actions\Humanizer.ahk
#Include ..\..\Actions\Click.ahk
#Include ..\..\Config\Config.ahk
#Include ..\..\Diagnostics\Logger.ahk
#Include ..\..\Diagnostics\WindowFocus.ahk
#Include ..\..\Diagnostics\Overlay.ahk

; ============================================================
; ThievingPhase - click the stall when ready, wait for slot 1 to
; fill, click it. No loot within timeout => detected, hand off to
; combat.
; ============================================================
class ThievingPhase extends Phase {
    __New(stallX, stallY, stallColor, stallColorTolerance, stallPollKey,
          firstSlotGate, inventory, lootWaitTimeoutMs, lootPollKey,
          runMode := false) {
        super.__New("thieving")
        this._stallX := stallX
        this._stallY := stallY
        this._stallColor := stallColor
        this._stallColorTolerance := stallColorTolerance
        this._stallPollKey := stallPollKey
        this._firstSlotGate := firstSlotGate
        this._inventory := inventory
        this._lootWaitTimeoutMs := lootWaitTimeoutMs
        this._lootPollKey := lootPollKey
        this._runMode := runMode
    }

    ResetForNewCycle() {
        ; No per-cycle scratch state to reset - this phase is stateless
        ; between ticks aside from the ctx it's given.
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "thieving"

        if (!ColorSearch.IsColorAt(this._stallX, this._stallY, this._stallColor, this._stallColorTolerance)) {
            ctx.waiter.After(ctx.timing, this._stallPollKey)
            return "thieving"
        }

        ctx.Log("ThievingPhase: Stall ready. Clicking.")
        ctx.clicker.ClickSettled(ctx, this._stallX, this._stallY, this._runMode)
        ctx.failsafe.ResetPhaseTimer(ctx)

        deadline := A_TickCount + this._lootWaitTimeoutMs
        loop {
            if (this._firstSlotGate.IsSet()) {
                this._inventory.SlotCenter(1, &slotX, &slotY)
                ctx.Log("ThievingPhase: Loot detected in slot 1. Clicking it.")
                ctx.clicker.ClickSettled(ctx, slotX, slotY, this._runMode)
                ctx.failsafe.ResetPhaseTimer(ctx)
                ctx.waiter.After(ctx.timing, this._stallPollKey)
                return "thieving"
            }
            if (A_TickCount >= deadline)
                break
            ctx.waiter.After(ctx.timing, this._lootPollKey)
        }

        ctx.Log("ThievingPhase: No loot after " this._lootWaitTimeoutMs "ms - assuming detected, waiting for combat.")
        return "waitCombat"
    }
}

; ============================================================
; Wiring
; ============================================================

iniPath := A_ScriptDir "\..\..\Config\auto-fruitstall.ini"

schema := Map(
    "runnerTickMs", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutThieving", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutCombat", Map("section", "Tunables", "type", "int"),
    "colorTolerance", Map("section", "Tunables", "type", "int"),
    "stallX", Map("section", "Stall", "type", "int"),
    "stallY", Map("section", "Stall", "type", "int"),
    "stallColor", Map("section", "Stall", "type", "color"),
    "stallPollMs", Map("section", "Stall", "type", "int"),
    "lootWaitTimeoutMs", Map("section", "Loot", "type", "int"),
    "lootPollMs", Map("section", "Loot", "type", "int"),
    "combatIndicatorX", Map("section", "Combat", "type", "int"),
    "combatIndicatorY", Map("section", "Combat", "type", "int"),
    "combatIndicatorTolerance", Map("section", "Combat", "type", "int"),
    "combatStartColor", Map("section", "Combat", "type", "color"),
    "combatKillColor", Map("section", "Combat", "type", "color"),
    "combatPollMs", Map("section", "Combat", "type", "int"),
    "retryClickAfterMs", Map("section", "Combat", "type", "int"),
    "combatStartTimeoutMs", Map("section", "Combat", "type", "int"),
    "postKillSettleDelayMs", Map("section", "Combat", "type", "int"),
    "clickSettleMs", Map("section", "ClickExecution", "type", "int"),
    "clickSettleJitterPercent", Map("section", "ClickExecution", "type", "int"),
    "ctrlHoldSettleMs", Map("section", "ClickExecution", "type", "int"),
    "runMode", Map("section", "Settings", "type", "int")
)
timingSchema := Map(
    "clickSettle", Map("section", "ClickExecution", "baseMsKey", "clickSettleMs", "jitterPercentKey", "clickSettleJitterPercent"),
    "ctrlHoldSettle", Map("section", "ClickExecution", "baseMsKey", "ctrlHoldSettleMs", "jitterPercentKey", "clickSettleJitterPercent"),
    "stallPoll", Map("section", "Stall", "baseMsKey", "stallPollMs"),
    "lootPoll", Map("section", "Loot", "baseMsKey", "lootPollMs"),
    "combatPoll", Map("section", "Combat", "baseMsKey", "combatPollMs"),
    "postKillSettle", Map("section", "Combat", "baseMsKey", "postKillSettleDelayMs")
)

botConfig := Config(iniPath, schema, timingSchema)
botConfig.Load()

botLogger := Logger(A_ScriptDir "\..\..\logs\auto-fruitstall-v4-debug.log")
botHumanizer := Humanizer(false)
botClicker := Clicker(botHumanizer)
botFailsafe := FailSafe(botLogger)
botWaiter := Waiter((baseMs, jitterPercent) => botHumanizer.Jitter(baseMs, jitterPercent))
botWindowFocus := WindowFocus()
botOverlay := Overlay(4, 10, 10)

ctx := EngineContext(botConfig, botLogger, botClicker, botFailsafe, botWaiter, botWindowFocus, botOverlay)

; Same 4x7 inventory grid every other bot uses - the layout never changes
; between accounts/sessions, so it's hardcoded rather than an ini value.
inventoryLayout := Map("firstX", 2099, "firstY", 801, "cols", 4, "rows", 7, "slotW", 72, "slotH", 64, "gapX", 12, "gapY", 8)
ctx.inventory := Inventory(inventoryLayout)

firstSlotGate := SlotGate(1, botConfig.Get("colorTolerance"), ctx.inventory)

combatIndicatorGate := PixelColorGate(
    botConfig.Get("combatIndicatorX"), botConfig.Get("combatIndicatorY"), botConfig.Get("combatIndicatorTolerance")
)

botThievingPhase := ThievingPhase(
    botConfig.Get("stallX"), botConfig.Get("stallY"), botConfig.Get("stallColor"), botConfig.Get("colorTolerance"),
    "stallPoll", firstSlotGate, ctx.inventory, botConfig.Get("lootWaitTimeoutMs"), "lootPoll",
    botConfig.Get("runMode")
)

botWaitCombatPhase := WaitCombatPhase(
    combatIndicatorGate, botConfig.Get("combatStartColor"), botConfig.Get("combatKillColor"),
    "combatPoll", botConfig.Get("retryClickAfterMs"), botConfig.Get("combatStartTimeoutMs"),
    "postKillSettle", "thieving", "thieving"
)

botEngine := Engine(ctx, botConfig.Get("runnerTickMs"))
ctx.engine := botEngine
botEngine.AddPhase(botThievingPhase, botConfig.Get("phaseTimeoutThieving"))
botEngine.AddPhase(botWaitCombatPhase, botConfig.Get("phaseTimeoutCombat"))

F5:: botEngine.Start("thieving")
F6:: {
    botEngine.Stop("Stopped (F6)")
    botOverlay.Clear()
}
