; ============================================================
; auto-attack.ahk - v3
;
; Combat loop:
;   1) Find nearest fully-filled 17x17 magenta block in calibrated area
;   2) Click its center
;   3) Wait for combat indicator pixel to turn green (combat started)
;   4) Wait for that pixel to change away from green (combat ended)
;   5) Repeat
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\lib\Tooltip.ahk
#Include ..\lib\Context.ahk
#Include ..\lib\Db.ahk
#Include ..\lib\Colors.ahk
#Include ..\lib\Safety.ahk
#Include ..\lib\Click.ahk
#Include ..\lib\Targeting.ahk
#Include ..\lib\Validate.ahk
#Include ..\lib\TaskRunner.ahk
#Include ..\lib\Log.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

global CONFIG := A_ScriptDir "\..\config\auto-attack.ini"
global LOG_FILE := A_ScriptDir "\..\logs\auto-attack-debug.log"
global ctx := NewBotContext(CONFIG)

EnsureDbVersion(CONFIG)
LoadConfig()

; ============================================================
; HOTKEYS
; ============================================================

F1:: SetCombatAreaCorner1()
F2:: SetCombatAreaCorner2()
F3:: CalibrateCharacterCenter()
F4:: CalibrateCombatIndicatorPoint()
F8:: DiagnosticFindTarget()

F5:: StartBot()
F6:: StopAndLog(ctx["runner"], "Stopped (F6)")
F7:: ClearConfigAndReload()

; ============================================================
; BOT LIFECYCLE
; ============================================================

StartBot() {
    global ctx, LOG_FILE
    if (!ValidateSetup())
        return

    if (ctx["runner"] != "" && ctx["runner"]["running"])
        StopTaskRunner(ctx["runner"], "Restarting...")

    ctx["runner"] := NewTaskRunner(CtxTunable(ctx, "runnerTickMs", 20))
    AddPhase(ctx["runner"], "fight", FightPhase, CtxTunable(ctx, "phaseTimeoutFight", 150000))
    StartTaskRunner(ctx["runner"], "fight")
    LogLine(LOG_FILE, "===== Auto-attack started =====")
    ShowTipFor("Auto-attack started", 1200)
}

StopAndLog(runner, reason) {
    global LOG_FILE
    LogLine(LOG_FILE, "STOPPED: " reason)
    if (runner != "")
        StopTaskRunner(runner, reason)
}

ClearConfigAndReload() {
    global CONFIG
    if FileExist(CONFIG)
        FileDelete(CONFIG)
    Reload()
}

; ============================================================
; PHASE
; ============================================================

FightPhase(runner) {
    global ctx, LOG_FILE
    static lastNoTargetLogAt := 0

    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "fight")

    region := CtxTargetRegion(ctx, "CombatArea")
    center := ctx["characterCenter"]
    indicator := ctx["combatIndicator"]
    indicatorColor := ctx["combatIndicatorColor"]

    acquired := AcquireSolidColorBlockTarget(
        ctx,
        region,
        center["x"],
        center["y"],
        CtxTunable(ctx, "blockSize", 17),
        CtxTunable(ctx, "attackClickCount", 1),
        CtxTunable(ctx, "attackClickDelayMs", 10)
    )

    if (!acquired) {
        if (A_TickCount - lastNoTargetLogAt > 2000) {
            lastNoTargetLogAt := A_TickCount
            LogLine(LOG_FILE,
                "fight: no target found (size=" CtxTunable(ctx, "blockSize", 17)
                ", tol=" region["tolerance"]
                ", region=" region["x1"] "," region["y1"] " to " region["x2"] "," region["y2"] ")")
        }
        Sleep(CtxTunable(ctx, "scanPollMs", 20))
        return GoToPhase(runner, "fight")
    }

    LogLine(LOG_FILE, "fight: target clicked")
    Sleep(CtxTunable(ctx, "attackSettleMs", 200))

    started := WaitForPixelColor(
        ctx,
        indicator["x"],
        indicator["y"],
        indicatorColor,
        CtxTunable(ctx, "indicatorTolerance", 20),
        CtxTunable(ctx, "combatStartTimeoutMs", 1000),
        CtxTunable(ctx, "combatConfirmTicks", 2),
        CtxTunable(ctx, "combatPollMs", 50)
    )

    if (!started) {
        LogLine(LOG_FILE, "fight: combat did not start in time - retry")
        return GoToPhase(runner, "fight")
    }

    ResetPhaseTimer(ctx["runner"])
    LogLine(LOG_FILE, "fight: combat started")

    ended := WaitForPixelColorChange(
        ctx,
        indicator["x"],
        indicator["y"],
        indicatorColor,
        CtxTunable(ctx, "indicatorTolerance", 20),
        CtxTunable(ctx, "combatKillTimeoutMs", 120000),
        CtxTunable(ctx, "combatConfirmTicks", 2),
        CtxTunable(ctx, "combatPollMs", 100)
    )

    if (!ended) {
        LogLine(LOG_FILE, "fight: combat end not detected in time - retry")
        return GoToPhase(runner, "fight")
    }

    ResetPhaseTimer(ctx["runner"])
    LogLine(LOG_FILE, "fight: combat ended")
    return GoToPhase(runner, "fight")
}

; ============================================================
; CALIBRATION HOTKEYS
; ============================================================

SetCombatAreaCorner1() {
    global ctx
    MouseGetPos(&mx, &my)
    ctx["combatAreaCorner1"] := Map("x", mx, "y", my)
    ShowTipFor("Combat area corner 1 set at " mx ", " my " - press F2 for corner 2", 2000)
}

SetCombatAreaCorner2() {
    global ctx, CONFIG
    if (!ctx.Has("combatAreaCorner1")) {
        ShowTipFor("Press F1 first to set corner 1", 1500)
        return
    }

    MouseGetPos(&mx, &my)
    c1 := ctx["combatAreaCorner1"]
    x1 := Min(c1["x"], mx)
    y1 := Min(c1["y"], my)
    x2 := Max(c1["x"], mx)
    y2 := Max(c1["y"], my)

    DbSetTargetRegion(CONFIG, "TargetRegion:CombatArea", 0xFF00FF, 0, x1, y1, x2, y2)
    ctx["targetRegions"]["CombatArea"] := DbGetTargetRegion(CONFIG, "TargetRegion:CombatArea")
    ShowTipFor("Combat area saved", 1500)
}

CalibrateCharacterCenter() {
    global ctx, CONFIG
    MouseGetPos(&mx, &my)
    DbSetPoint(CONFIG, "Point:CharacterCenter", "pos", mx, my)
    ctx["characterCenter"] := DbGetPoint(CONFIG, "Point:CharacterCenter", "pos", 0, 0)
    ShowTipFor("Character center saved at " mx ", " my, 1500)
}

CalibrateCombatIndicatorPoint() {
    global ctx, CONFIG
    MouseGetPos(&mx, &my)
    DbSetPoint(CONFIG, "Point:CombatIndicator", "pos", mx, my)
    ctx["combatIndicator"] := DbGetPoint(CONFIG, "Point:CombatIndicator", "pos", 0, 0)
    ShowTipFor("Combat indicator point saved at " mx ", " my, 1500)
}

DiagnosticFindTarget() {
    global ctx, LOG_FILE
    region := CtxTargetRegion(ctx, "CombatArea")
    center := ctx["characterCenter"]
    size := CtxTunable(ctx, "blockSize", 17)

    if (FindNearestSolidColorBlockCenter(region["x1"], region["y1"], region["x2"], region["y2"],
        center["x"], center["y"], region["color"], region["tolerance"], &tx, &ty, size)) {
        LogLine(LOG_FILE, "diag: found target at " tx "," ty " (size=" size ", tol=" region["tolerance"] ")")
        ShowTipFor("Target found at " tx ", " ty, 1800)
    } else {
        LogLine(LOG_FILE,
            "diag: no target found (size=" size ", tol=" region["tolerance"]
            ", region=" region["x1"] "," region["y1"] " to " region["x2"] "," region["y2"] ")")
        ShowTipFor("No target block found", 1800)
    }
}

; ============================================================
; CONFIG
; ============================================================

LoadConfig() {
    global ctx, CONFIG, LOG_FILE

    ctx["logFile"] := LOG_FILE

    ; Tunables
    ctx["tunables"]["runnerTickMs"] := DbGet(CONFIG, "Tunables", "runnerTickMs", 20, "int")
    ctx["tunables"]["blockSize"] := DbGet(CONFIG, "Tunables", "blockSize", 17, "int")
    ctx["tunables"]["scanPollMs"] := DbGet(CONFIG, "Tunables", "scanPollMs", 20, "int")
    ctx["tunables"]["attackClickCount"] := DbGet(CONFIG, "Tunables", "attackClickCount", 1, "int")
    ctx["tunables"]["attackClickDelayMs"] := DbGet(CONFIG, "Tunables", "attackClickDelayMs", 10, "int")
    ctx["tunables"]["attackSettleMs"] := DbGet(CONFIG, "Tunables", "attackSettleMs", 200, "int")
    ctx["tunables"]["indicatorTolerance"] := DbGet(CONFIG, "Tunables", "indicatorTolerance", 20, "int")
    ctx["tunables"]["combatStartTimeoutMs"] := DbGet(CONFIG, "Tunables", "combatStartTimeoutMs", 1000, "int")
    ctx["tunables"]["combatKillTimeoutMs"] := DbGet(CONFIG, "Tunables", "combatKillTimeoutMs", 120000, "int")
    ctx["tunables"]["combatConfirmTicks"] := DbGet(CONFIG, "Tunables", "combatConfirmTicks", 2, "int")
    ctx["tunables"]["combatPollMs"] := DbGet(CONFIG, "Tunables", "combatPollMs", 100, "int")
    ctx["tunables"]["phaseTimeoutFight"] := DbGet(CONFIG, "Tunables", "phaseTimeoutFight", 150000, "int")

    DbSet(CONFIG, "Tunables", "runnerTickMs", ctx["tunables"]["runnerTickMs"], "int")
    DbSet(CONFIG, "Tunables", "blockSize", ctx["tunables"]["blockSize"], "int")
    DbSet(CONFIG, "Tunables", "scanPollMs", ctx["tunables"]["scanPollMs"], "int")
    DbSet(CONFIG, "Tunables", "attackClickCount", ctx["tunables"]["attackClickCount"], "int")
    DbSet(CONFIG, "Tunables", "attackClickDelayMs", ctx["tunables"]["attackClickDelayMs"], "int")
    DbSet(CONFIG, "Tunables", "attackSettleMs", ctx["tunables"]["attackSettleMs"], "int")
    DbSet(CONFIG, "Tunables", "indicatorTolerance", ctx["tunables"]["indicatorTolerance"], "int")
    DbSet(CONFIG, "Tunables", "combatStartTimeoutMs", ctx["tunables"]["combatStartTimeoutMs"], "int")
    DbSet(CONFIG, "Tunables", "combatKillTimeoutMs", ctx["tunables"]["combatKillTimeoutMs"], "int")
    DbSet(CONFIG, "Tunables", "combatConfirmTicks", ctx["tunables"]["combatConfirmTicks"], "int")
    DbSet(CONFIG, "Tunables", "combatPollMs", ctx["tunables"]["combatPollMs"], "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutFight", ctx["tunables"]["phaseTimeoutFight"], "int")

    ; Settings
    ctx["runMode"] := DbGet(CONFIG, "Settings", "runMode", false, "bool")
    DbSet(CONFIG, "Settings", "runMode", ctx["runMode"], "bool")

    ; Target region and points
    ctx["targetRegions"]["CombatArea"] := DbGetTargetRegion(CONFIG, "TargetRegion:CombatArea")
    r := ctx["targetRegions"]["CombatArea"]
    if (r["color"] = -1 || !IsRegionValid(r["x1"], r["y1"], r["x2"], r["y2"])) {
        DbSetTargetRegion(CONFIG, "TargetRegion:CombatArea", 0xFF00FF, 0, 0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1)
        ctx["targetRegions"]["CombatArea"] := DbGetTargetRegion(CONFIG, "TargetRegion:CombatArea")
    }

    ctx["characterCenter"] := DbGetPoint(CONFIG, "Point:CharacterCenter", "pos", 0, 0)
    ctx["combatIndicator"] := DbGetPoint(CONFIG, "Point:CombatIndicator", "pos", 1652, 1235)
    ctx["combatIndicatorColor"] := DbGet(CONFIG, "Tunables", "combatIndicatorColor", 0x068C37, "color")
    DbSet(CONFIG, "Tunables", "combatIndicatorColor", ctx["combatIndicatorColor"], "color")
}

; ============================================================
; VALIDATION
; ============================================================

ValidateSetup() {
    global ctx
    v := NewValidator()

    RequireTargetRegion(v, "F1/F2 - combat area", CtxTargetRegion(ctx, "CombatArea"))
    RequireCoord(v, "F3 - character center", ctx["characterCenter"]["x"], ctx["characterCenter"]["y"])
    RequireCoord(v, "F4 - combat indicator point", ctx["combatIndicator"]["x"], ctx["combatIndicator"]["y"])

    return ShowValidationErrors(v)
}
