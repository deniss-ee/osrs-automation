; ============================================================
; auto-agility.ahk - v1 (Agility Course Runner)
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\lib\Tooltip.ahk
#Include ..\lib\Context.ahk
#Include ..\lib\Db.ahk
#Include ..\lib\Colors.ahk
#Include ..\lib\Images.ahk
#Include ..\lib\Safety.ahk
#Include ..\lib\Grid.ahk
#Include ..\lib\Click.ahk
#Include ..\lib\Slots.ahk
#Include ..\lib\Targeting.ahk
#Include ..\lib\Validate.ahk
#Include ..\lib\TaskRunner.ahk
#Include ..\lib\Log.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

global CONFIG   := A_ScriptDir "\..\config\auto-agility.ini"
global LOG_FILE := A_ScriptDir "\..\logs\auto-agility-debug.log"
global ctx      := NewBotContext(CONFIG)

; Define the obstacle sequence
global STEPS := [
    Map("w", 42, "h", 42, "x", 807, "y", 775),
    Map("w", 44, "h", 44, "x", 1069, "y", 699),
    Map("w", 38, "h", 38, "x", 865, "y", 794),
    Map("w", 64, "h", 64, "x", 976, "y", 892),
    Map("w", 43, "h", 65, "x", 1267, "y", 688),
    Map("w", 87, "h", 90, "x", 1191, "y", 503),
    Map("w", 18, "h", 66, "x", 994, "y", 174)
]

EnsureDbVersion(CONFIG)
LoadConfig()

; ============================================================
; HOTKEYS
; ============================================================

F5:: StartBot()
F6:: StopAndLog(ctx["runner"], "Stopped (F6)")
F7:: ClearConfigAndReload()

; ============================================================
; BOT LIFECYCLE
; ============================================================

StartBot() {
    global ctx
    if (!ValidateSetup())
        return
    if (ctx["runner"] != "" && ctx["runner"]["running"])
        StopTaskRunner(ctx["runner"], "Restarting...")
    
    ctx["runner"] := NewTaskRunner(50) ; 50ms fast ticks
    AddPhase(ctx["runner"], "agility", AgilityPhase, CtxTunable(ctx, "phaseTimeoutAgility", 60000))

    ctx["currentStep"] := 1
    StartTaskRunner(ctx["runner"], "agility")
    TickTaskRunner(ctx["runner"])
    LogLine(LOG_FILE, "===== Agility Runner started =====")
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
; PHASES
; ============================================================

AgilityPhase(runner) {
    global ctx, LOG_FILE, STEPS
    static lastLogTime := 0
    static lastClickTime := 0

    if (!RequireOsrsWindowActive(ctx)) {
        if (A_TickCount - lastLogTime > 2000) {
            lastLogTime := A_TickCount
            LogLine(LOG_FILE, "AgilityPhase tick: PAUSED (RuneLite not focused)")
        }
        return GoToPhase(runner, "agility")
    }

    currentStep := ctx["currentStep"]
    step := STEPS[currentStep]
    searchTol := CtxTunable(ctx, "searchTolerancePx", 15)
    colorTolerance := CtxTunable(ctx, "colorTolerance", 10)

    ; Search box around the expected top-left coordinate of the highlight
    x1 := step["x"] - searchTol
    y1 := step["y"] - searchTol
    x2 := step["x"] + searchTol
    y2 := step["y"] + searchTol

    ; Search for green highlight of expected dimensions
    if (FindFilledBlock(x1, y1, x2, y2, 0x00FF00, colorTolerance, step["w"], step["h"], &cx, &cy)) {
        cooldown := CtxTunable(ctx, "clickCooldownMs", 3000)
        if (A_TickCount - lastClickTime > cooldown) {
            HumanClick(cx, cy, 0, 0, ctx["runMode"])
            lastClickTime := A_TickCount
            LogLine(LOG_FILE, "Agility: Clicked Step " currentStep " at [" cx "," cy "] (" step["w"] "x" step["h"] ")")
            ShowTipFor("Agility: Running obstacle " currentStep, 1500)

            ; Advance to next step immediately (the next tick will wait for Step i+1 highlight)
            nextStep := currentStep + 1
            if (nextStep > STEPS.Length)
                nextStep := 1
            ctx["currentStep"] := nextStep
            ResetPhaseTimer(ctx["runner"])
        }
    } else {
        if (A_TickCount - lastLogTime > 2000) {
            lastLogTime := A_TickCount
            LogLine(LOG_FILE, "Agility: Waiting for Step " currentStep " highlight (" step["w"] "x" step["h"] " at " step["x"] "," step["y"] ")")
        }
        ShowTip("Agility: Waiting for obstacle " currentStep "...")

        ; Failsafe: if we timed out waiting for too long, check if the previous step's highlight is still visible
        failsafeTimeout := CtxTunable(ctx, "failsafeTimeoutMs", 15000)
        if (A_TickCount - lastClickTime > failsafeTimeout) {
            prevStep := currentStep - 1
            if (prevStep < 1)
                prevStep := STEPS.Length
            pStep := STEPS[prevStep]
            
            px1 := pStep["x"] - searchTol
            py1 := pStep["y"] - searchTol
            px2 := pStep["x"] + searchTol
            py2 := pStep["y"] + searchTol

            if (FindFilledBlock(px1, py1, px2, py2, 0x00FF00, colorTolerance, pStep["w"], pStep["h"], &pcx, &pcy)) {
                LogLine(LOG_FILE, "Agility Failsafe: Timed out waiting for Step " currentStep ", but Step " prevStep " is still visible. Reverting step index.")
                ctx["currentStep"] := prevStep
                lastClickTime := 0 ; permit instant click on revert
            }
        }
    }

    return GoToPhase(runner, "agility")
}

; ============================================================
; HELPERS
; ============================================================

VerifyBlock(x, y, color, tol, reqW, reqH) {
    cx := x + reqW // 2
    cy := y + reqH // 2

    ; We verify that it is AT LEAST checkW x checkH solid fill.
    ; Checking 75% of the requested size is safe against edge anti-aliasing.
    checkW := reqW * 3 // 4
    checkH := reqH * 3 // 4

    ; Check internal points using type-safe IsColorAt
    if (!IsColorAt(cx, cy, color, tol))
        return false
    if (!IsColorAt(x, y + checkH // 2, color, tol))
        return false
    if (!IsColorAt(x + checkW // 2, y, color, tol))
        return false
    if (!IsColorAt(x + checkW - 1, y + checkH // 2, color, tol))
        return false
    if (!IsColorAt(x + checkW // 2, y + checkH - 1, color, tol))
        return false

    return true
}

FindFilledBlock(x1, y1, x2, y2, color, tol, reqW, reqH, &cx, &cy) {
    if (x1 > x2 || y1 > y2)
        return false

    if (!PixelSearch(&foundX, &foundY, x1, y1, x2, y2, color, tol))
        return false

    if (VerifyBlock(foundX, foundY, color, tol, reqW, reqH)) {
        cx := foundX + reqW // 2
        cy := foundY + reqH // 2
        return true
    }

    ; Recursive search to cover the remaining areas:
    ; 1. The rest of the current horizontal line segment
    if (FindFilledBlock(foundX + 1, foundY, x2, foundY, color, tol, reqW, reqH, &cx, &cy))
        return true

    ; 2. All subsequent lines below the current pixel row
    if (FindFilledBlock(x1, foundY + 1, x2, y2, color, tol, reqW, reqH, &cx, &cy))
        return true

    return false
}

; ============================================================
; CONFIG
; ============================================================

LoadConfig() {
    global ctx, CONFIG

    ; --- Tunables (read from ini or write defaults) ---
    ctx["tunables"]["colorTolerance"]        := DbGet(CONFIG, "Tunables", "colorTolerance",        10,    "int")
    ctx["tunables"]["searchTolerancePx"]     := DbGet(CONFIG, "Tunables", "searchTolerancePx",     15,    "int")
    ctx["tunables"]["clickCooldownMs"]       := DbGet(CONFIG, "Tunables", "clickCooldownMs",       3000,  "int")
    ctx["tunables"]["failsafeTimeoutMs"]     := DbGet(CONFIG, "Tunables", "failsafeTimeoutMs",     15000, "int")
    ctx["tunables"]["phaseTimeoutAgility"]   := DbGet(CONFIG, "Tunables", "phaseTimeoutAgility",   60000, "int")

    ; Write back
    DbSet(CONFIG, "Tunables", "colorTolerance",        ctx["tunables"]["colorTolerance"],        "int")
    DbSet(CONFIG, "Tunables", "searchTolerancePx",     ctx["tunables"]["searchTolerancePx"],     "int")
    DbSet(CONFIG, "Tunables", "clickCooldownMs",       ctx["tunables"]["clickCooldownMs"],       "int")
    DbSet(CONFIG, "Tunables", "failsafeTimeoutMs",     ctx["tunables"]["failsafeTimeoutMs"],     "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutAgility",   ctx["tunables"]["phaseTimeoutAgility"],   "int")

    ; --- Settings ---
    ctx["runMode"] := DbGet(CONFIG, "Settings", "runMode", true, "bool")
    DbSet(CONFIG, "Settings", "runMode", ctx["runMode"], "bool")
}

ValidateSetup() {
    return true
}
