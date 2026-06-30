; ============================================================
; auto-motherlode.ahk - v3 (Initial Phase: Dynamic Vein Tracking)
;
; Cycle:
;   1. Searches dynamic area (default 734, 570 to 1454, 930) for the nearest active
;      vein block (#00FF00 or #00CE00) relative to screen center (960, 540).
;   2. Finds the exact center using centroid calculation.
;   3. Clicks the centroid to mine and saves the position.
;   4. Monitors a local 30x30 box around the clicked coordinate.
;   5. When the green fill is gone, switches to the next nearest vein instantly.
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

global CONFIG   := A_ScriptDir "\..\config\auto-motherlode.ini"
global LOG_FILE := A_ScriptDir "\..\logs\auto-motherlode-debug.log"
global ctx      := NewBotContext(CONFIG)

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
    
    ctx["runner"] := NewTaskRunner(50) ; Fast 50ms ticks
    AddPhase(ctx["runner"], "mine", MinePhase, CtxTunable(ctx, "phaseTimeoutMine", 180000))

    StartTaskRunner(ctx["runner"], "mine")
    TickTaskRunner(ctx["runner"])
    LogLine(LOG_FILE, "===== Motherlode Miner started =====")
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

MinePhase(runner) {
    global ctx, LOG_FILE
    static lastLogTime := 0
    static lastClickTime := 0
    static prevVx := 0
    static prevVy := 0
    static stableTicks := 0

    if (!RequireOsrsWindowActive(ctx)) {
        if (A_TickCount - lastLogTime > 2000) {
            lastLogTime := A_TickCount
            LogLine(LOG_FILE, "MinePhase tick: PAUSED (RuneLite not focused)")
        }
        return GoToPhase(runner, "mine")
    }

    tol := CtxTunable(ctx, "colorTolerance", 20)
    indicatorSlot := CtxTunable(ctx, "indicatorSlot", 28)
    slotOccupied := IsSlotOccupied(indicatorSlot, tol)

    ; 1. Check if inventory is full
    if (slotOccupied) {
        LogLine(LOG_FILE, "MinePhase: inventory full - stopping bot")
        StopAndLog(runner, "Inventory full - stopping")
        return GoToPhase(runner, "mine")
    }

    searchRegion := ctx["targetRegions"]["SearchRegion"]
    refPoint := ctx["returnWalkPoint"] ; Character center (960, 540)
    clickCooldown := CtxTunable(ctx, "clickCooldownMs", 3000)

    ; Find nearest active vein block
    foundVein := FindNearestVein(searchRegion["x1"], searchRegion["y1"], searchRegion["x2"], searchRegion["y2"], refPoint["x"], refPoint["y"], tol, &vx, &vy)

    if (foundVein) {
        ; Check if coordinate is stable (meaning we have arrived and are standing still mining)
        isStable := (Abs(vx - prevVx) <= 2 && Abs(vy - prevVy) <= 2)
        if (isStable) {
            stableTicks++
        } else {
            stableTicks := 0
        }

        prevVx := vx
        prevVy := vy

        dx := vx - refPoint["x"]
        dy := vy - refPoint["y"]
        dist := Sqrt(dx*dx + dy*dy)

        if (A_TickCount - lastLogTime > 2000) {
            lastLogTime := A_TickCount
            LogLine(LOG_FILE, "MinePhase tick: ACTIVE, nearestVeinDist=" dist "px stableTicks=" stableTicks)
        }

        ; We consider ourselves "mining" if the vein coordinates have been stable for at least 3 ticks (150ms)
        if (stableTicks >= 3) {
            ShowTip("Miner: mining vein (static)...")
        } else {
            ; Click to start mining (rate-limited to prevent spamming while walking)
            if (A_TickCount - lastClickTime > clickCooldown) {
                HumanClick(vx, vy, 0, 0, ctx["runMode"])
                lastClickTime := A_TickCount
                stableTicks := 0 ; reset stability on click
                LogLine(LOG_FILE, "MinePhase: clicked vein at [" vx "," vy "] (dist=" dist "px)")
                ShowTipFor("Miner: moving to vein...", 1500)
            } else {
                ShowTip("Miner: walking to vein...")
            }
        }
    } else {
        prevVx := 0
        prevVy := 0
        stableTicks := 0
        if (A_TickCount - lastLogTime > 2000) {
            lastLogTime := A_TickCount
            LogLine(LOG_FILE, "MinePhase tick: ACTIVE, no veins found")
        }
        ShowTip("Miner: waiting for veins...")
    }

    return GoToPhase(runner, "mine")
}

; ============================================================
; HELPERS
; ============================================================

FindNearestColorBox(x1, y1, x2, y2, refX, refY, color, tol, &foundX, &foundY) {
    ; Expanding boxes: 50, 100, 200, then full region
    steps := [50, 100, 200]
    for dist in steps {
        bx1 := Max(x1, refX - dist)
        by1 := Max(y1, refY - dist)
        bx2 := Min(x2, refX + dist)
        by2 := Min(y2, refY + dist)
        if (IsColorInRegion(bx1, by1, bx2, by2, color, tol, &foundX, &foundY)) {
            return true
        }
    }
    ; Fallback to full region
    return IsColorInRegion(x1, y1, x2, y2, color, tol, &foundX, &foundY)
}

FindNearestVein(x1, y1, x2, y2, refX, refY, tol, &vx, &vy) {
    ; Search for bright green vein
    if (FindNearestColorBox(x1, y1, x2, y2, refX, refY, 0x00FF00, tol, &seedX, &seedY)) {
        vx := seedX + 8
        vy := seedY + 8
        return true
    }
    ; Search for dark green vein
    if (FindNearestColorBox(x1, y1, x2, y2, refX, refY, 0x00CE00, tol, &seedX, &seedY)) {
        vx := seedX + 8
        vy := seedY + 8
        return true
    }
    return false
}

IsVeinStillActive(vx, vy, tol) {
    x1 := Max(734, vx - 15)
    y1 := Max(570, vy - 15)
    x2 := Min(1454, vx + 15)
    y2 := Min(930, vy + 15)
    return IsColorInRegion(x1, y1, x2, y2, 0x00FF00, tol) || IsColorInRegion(x1, y1, x2, y2, 0x00CE00, tol)
}

; ============================================================
; CONFIG
; ============================================================

LoadConfig() {
    global ctx, CONFIG

    ; --- Tunables (read from ini or write defaults) ---
    ctx["tunables"]["colorTolerance"]        := DbGet(CONFIG, "Tunables", "colorTolerance",        20,     "int")
    ctx["tunables"]["phaseTimeoutMine"]      := DbGet(CONFIG, "Tunables", "phaseTimeoutMine",      180000, "int")
    ctx["tunables"]["miningActiveRadius"]    := DbGet(CONFIG, "Tunables", "miningActiveRadius",    95,     "int")
    ctx["tunables"]["indicatorSlot"]         := DbGet(CONFIG, "Settings", "indicatorSlot",         28,     "int")

    ; Write back
    DbSet(CONFIG, "Tunables", "colorTolerance",        ctx["tunables"]["colorTolerance"],        "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutMine",      ctx["tunables"]["phaseTimeoutMine"],      "int")
    DbSet(CONFIG, "Tunables", "miningActiveRadius",    ctx["tunables"]["miningActiveRadius"],    "int")

    ; --- Settings ---
    ctx["runMode"] := DbGet(CONFIG, "Settings", "runMode", true, "bool")
    DbSet(CONFIG, "Settings", "runMode", ctx["runMode"], "bool")
    DbSet(CONFIG, "Settings", "indicatorSlot",         ctx["tunables"]["indicatorSlot"],         "int")

    ; --- Character Screen Reference Point ---
    ctx["returnWalkPoint"] := DbGetPoint(CONFIG, "Settings", "characterCenter", 960, 540)
    if (ctx["returnWalkPoint"]["x"] = 0 && ctx["returnWalkPoint"]["y"] = 0) {
        DbSetPoint(CONFIG, "Settings", "characterCenter", 960, 540)
        ctx["returnWalkPoint"] := DbGetPoint(CONFIG, "Settings", "characterCenter", 960, 540)
    }

    ; --- Large Vein Search Region ---
    ctx["targetRegions"]["SearchRegion"] := DbGetTargetRegion(CONFIG, "TargetRegion:SearchRegion")
    if (ctx["targetRegions"]["SearchRegion"]["color"] = -1) {
        DbSetTargetRegion(CONFIG, "TargetRegion:SearchRegion", 0x00FF00, 20, 734, 570, 1454, 930)
        ctx["targetRegions"]["SearchRegion"] := DbGetTargetRegion(CONFIG, "TargetRegion:SearchRegion")
    }
}

ValidateSetup() {
    global ctx
    v := NewValidator()

    sr := ctx["targetRegions"]["SearchRegion"]
    RequireRegion(v, "Search region", sr["x1"], sr["y1"], sr["x2"], sr["y2"])

    pt := ctx["returnWalkPoint"]
    if (pt["x"] = 0 && pt["y"] = 0)
        v["errors"].Push("Character center reference is not calibrated")

    return ShowValidationErrors(v)
}
