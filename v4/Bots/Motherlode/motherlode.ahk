; ============================================================
; motherlode.ahk
; v4 entry point for the Motherlode Mine bot. Wires Engine +
; Config + Timing + Detection + Actions + Interfaces together
; for this bot only - this file has no logic of its own beyond
; construction and hotkeys. Currently a no-op skeleton (MinePhase
; is a stub); real phase logic is ported from
; scripts/auto-motherlode-v2.ahk in Phase 4/5.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\..\Core\Engine.ahk
#Include ..\..\Core\EngineContext.ahk
#Include ..\..\Core\FailSafe.ahk
#Include ..\..\Timing\Waiter.ahk
#Include ..\..\Detection\TargetLock.ahk
#Include ..\..\Detection\DynamicTarget.ahk
#Include ..\..\Actions\Humanizer.ahk
#Include ..\..\Actions\Click.ahk
#Include ..\..\Config\Config.ahk
#Include ..\..\Diagnostics\Logger.ahk
#Include MinePhase.ahk

; --- Config schema: every .ini key this bot needs, declared up front ---
schema := Map(
    "runnerTickMs", Map("section", "Tunables", "type", "int"),
    "mineStableTicks", Map("section", "Tunables", "type", "int"),
    "colorTolerance", Map("section", "Tunables", "type", "int")
)
timingSchema := Map(
    "mineClickCooldown", Map("section", "Tunables", "baseMsKey", "clickCooldownMs")
)

iniPath := A_ScriptDir "\..\..\..\config\auto-motherlode-v2.ini"
botConfig := Config(iniPath, schema, timingSchema)
botConfig.Load()

botLogger := Logger(A_ScriptDir "\..\..\..\logs\auto-motherlode-v4-debug.log")
botHumanizer := Humanizer(false)
botClicker := Clicker(botHumanizer)
botFailsafe := FailSafe(botLogger)
botWaiter := Waiter((baseMs, jitterPercent) => botHumanizer.Jitter(baseMs, jitterPercent))

ctx := EngineContext(botConfig, botLogger, botClicker, botFailsafe, botWaiter)

; --- Detection wiring for the mine phase (stubbed target, real region TBD in Phase 4/5) ---
lock := TargetLock(botConfig.Get("mineStableTicks"), 2)
region := Map("x1", 734, "y1", 570, "x2", 1454, "y2", 930)
vein := ColorBlockTarget(region, 0x00FF00, botConfig.Get("colorTolerance"), 15, 15, lock)

botEngine := Engine(ctx, botConfig.Get("runnerTickMs"))
botEngine.AddPhase(MinePhase(vein))

F5:: botEngine.Start("mine")
F6:: botEngine.Stop("Stopped (F6)")
