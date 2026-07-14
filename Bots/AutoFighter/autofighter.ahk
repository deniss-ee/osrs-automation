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
#Include ..\..\Core\SharedPhases.ahk
#Include ..\..\Timing\Waiter.ahk
#Include ..\..\Detection\ColorSearch.ahk
#Include ..\..\Detection\Telemetry.ahk
#Include ..\..\Actions\Humanizer.ahk
#Include ..\..\Actions\Click.ahk
#Include ..\..\Config\Config.ahk
#Include ..\..\Diagnostics\Logger.ahk
#Include ..\..\Diagnostics\WindowFocus.ahk
#Include ..\..\Diagnostics\Overlay.ahk

; ScanAndAttackPhase/WaitCombatPhase now live in Core/SharedPhases.ahk,
; shared with Bots/AutoFighterLoot - see that file for full design notes
; (stale-kill-color guard, retry-on-missed-click, etc.). This bot passes
; "scanAndAttack" as WaitCombatPhase's killNextPhaseName (its default),
; since it has no loot-pickup step.

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
    botConfig.Get("targetWaitTimeoutMs"), "waitCombat", botConfig.Get("runMode")
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
