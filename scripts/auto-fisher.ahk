; ============================================================
; auto-fisher.ahk - v3 (Simplified Fishing Script)
;
; Cycle:
;   1. Search the calibrated fishing area for the lobster spot icon (lobster.png).
;   2. If found, click it to start fishing and wait for it to settle.
;   3. Acquire and track the fishing spot using a sliding box.
;   4. Stop the bot immediately once inventory slot 28 becomes occupied.
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
#Include ..\lib\Validate.ahk
#Include ..\lib\TaskRunner.ahk
#Include ..\lib\Log.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

global CONFIG := A_ScriptDir "\..\config\auto-fisher.ini"
global LOG_FILE := A_ScriptDir "\..\logs\auto-fisher-debug.log"
global ctx := NewBotContext(CONFIG)

global fishAreaCorner1 := ""

EnsureDbVersion(CONFIG)
LoadConfig()

; ============================================================
; HOTKEYS
; ============================================================

F5:: StartBot()
F6:: StopAndLog(ctx["runner"], "Stopped (F6)")
F7:: ClearConfigAndReload()
F1:: SetCorner1()
F2:: SetCorner2()

; ============================================================
; CALIBRATION HELPERS
; ============================================================

SetCorner1() {
    global fishAreaCorner1
    MouseGetPos(&mx, &my)
    fishAreaCorner1 := Map("x", mx, "y", my)
    ShowTipFor("Fishing area corner 1 set at " mx ", " my " - now hover opposite corner and press F2", 2000)
}

SetCorner2() {
    global fishAreaCorner1, CONFIG
    if (fishAreaCorner1 = "") {
        ShowTipFor("Press F1 first to set the other corner", 1500)
        return
    }
    MouseGetPos(&mx, &my)
    x1 := Min(fishAreaCorner1["x"], mx)
    y1 := Min(fishAreaCorner1["y"], my)
    x2 := Max(fishAreaCorner1["x"], mx)
    y2 := Max(fishAreaCorner1["y"], my)
    
    DbSetRegion(CONFIG, "FishArea", x1, y1, x2, y2)
    ShowTipFor("Fishing area saved: (" x1 ", " y1 ") to (" x2 ", " y2 ")", 2000)
    LoadConfig()
}

; ============================================================
; CONFIG LOAD
; ============================================================

LoadConfig() {
    global ctx, CONFIG

    ; --- Tunables (read from ini or write defaults) ---
    ctx["tunables"]["colorTolerance"]            := DbGet(CONFIG, "Tunables", "colorTolerance",            5,      "int")
    ctx["tunables"]["indicatorSlot"]             := DbGet(CONFIG, "Tunables", "indicatorSlot",             28,     "int")
    ctx["tunables"]["fishSpotRadius"]            := DbGet(CONFIG, "Tunables", "fishSpotRadius",            70,     "int")
    ctx["tunables"]["fishSpotGoneConfirmTicks"]  := DbGet(CONFIG, "Tunables", "fishSpotGoneConfirmTicks",  5,      "int")
    ctx["tunables"]["fishSettleMs"]              := DbGet(CONFIG, "Tunables", "fishSettleMs",              600,    "int")
    ctx["tunables"]["fishAcquireTimeoutMs"]      := DbGet(CONFIG, "Tunables", "fishAcquireTimeoutMs",      10000,  "int")
    ctx["tunables"]["fishPollMs"]                := DbGet(CONFIG, "Tunables", "fishPollMs",                150,    "int")
    ctx["tunables"]["fishTimeoutMs"]              := DbGet(CONFIG, "Tunables", "fishTimeoutMs",              900000, "int")
    ctx["tunables"]["phaseTimeoutFish"]          := DbGet(CONFIG, "Tunables", "phaseTimeoutFish",          45000,  "int")
    ctx["tunables"]["fishImgWidth"]              := DbGet(CONFIG, "Tunables", "fishImgWidth",              64,     "int")
    ctx["tunables"]["fishImgHeight"]             := DbGet(CONFIG, "Tunables", "fishImgHeight",             48,     "int")
    ctx["tunables"]["fishImgOptions"]            := DbGet(CONFIG, "Tunables", "fishImgOptions",            "*Trans0x00FF00 *20", "string")

    ; Write back
    DbSet(CONFIG, "Tunables", "colorTolerance",            ctx["tunables"]["colorTolerance"],            "int")
    DbSet(CONFIG, "Tunables", "indicatorSlot",             ctx["tunables"]["indicatorSlot"],             "int")
    DbSet(CONFIG, "Tunables", "fishSpotRadius",            ctx["tunables"]["fishSpotRadius"],            "int")
    DbSet(CONFIG, "Tunables", "fishSpotGoneConfirmTicks",  ctx["tunables"]["fishSpotGoneConfirmTicks"],  "int")
    DbSet(CONFIG, "Tunables", "fishSettleMs",              ctx["tunables"]["fishSettleMs"],              "int")
    DbSet(CONFIG, "Tunables", "fishAcquireTimeoutMs",      ctx["tunables"]["fishAcquireTimeoutMs"],      "int")
    DbSet(CONFIG, "Tunables", "fishPollMs",                ctx["tunables"]["fishPollMs"],                "int")
    DbSet(CONFIG, "Tunables", "fishTimeoutMs",              ctx["tunables"]["fishTimeoutMs"],              "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutFish",          ctx["tunables"]["phaseTimeoutFish"],          "int")
    DbSet(CONFIG, "Tunables", "fishImgWidth",              ctx["tunables"]["fishImgWidth"],              "int")
    DbSet(CONFIG, "Tunables", "fishImgHeight",             ctx["tunables"]["fishImgHeight"],             "int")
    DbSet(CONFIG, "Tunables", "fishImgOptions",            ctx["tunables"]["fishImgOptions"],            "string")

    ; --- Settings ---
    ctx["runMode"] := DbGet(CONFIG, "Settings", "runMode", false, "bool")
    DbSet(CONFIG, "Settings", "runMode", ctx["runMode"], "bool")

    ; --- Regions ---
    ctx["targetRegions"]["FishArea"] := DbGetRegion(CONFIG, "FishArea")

    ; --- Images ---
    ctx["images"]["FishImg"] := Map(
        "file", A_ScriptDir "\..\images\lobster.png",
        "options", ctx["tunables"]["fishImgOptions"]
    )
}

; ============================================================
; SETUP VALIDATION
; ============================================================

ValidateSetup() {
    global ctx
    v := NewValidator()

    fa := ctx["targetRegions"]["FishArea"]
    RequireRegion(v, "F1/F2 - fishing area", fa["x1"], fa["y1"], fa["x2"], fa["y2"])
    
    fishImg := ctx["images"]["FishImg"]
    RequireFile(v, "lobster.png (fishing spot image)", fishImg["file"])

    return ShowValidationErrors(v)
}

; ============================================================
; BOT LIFECYCLE
; ============================================================

StartBot() {
    global ctx
    LoadConfig()
    if (!ValidateSetup())
        return
    if (ctx["runner"] != "" && ctx["runner"]["running"])
        StopTaskRunner(ctx["runner"], "Restarting...")

    ctx["runner"] := NewTaskRunner(50) ; 50ms fast ticks
    AddPhase(ctx["runner"], "fish", FishPhase, CtxTunable(ctx, "phaseTimeoutFish", 45000))

    StartTaskRunner(ctx["runner"], "fish")
    TickTaskRunner(ctx["runner"])
    LogLine(LOG_FILE, "===== Fisher started =====")
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

FishPhase(runner) {
    global ctx, LOG_FILE
    static lastLogTime := 0
    static lastSearchTipAt := 0

    if (!RequireOsrsWindowActive(ctx)) {
        if (A_TickCount - lastLogTime > 2000) {
            lastLogTime := A_TickCount
            LogLine(LOG_FILE, "FishPhase tick: PAUSED (RuneLite not focused)")
        }
        return GoToPhase(runner, "fish")
    }

    tol := CtxTunable(ctx, "colorTolerance", 5)
    indicatorSlot := CtxTunable(ctx, "indicatorSlot", 28)

    ; 1. Check if inventory indicator slot is occupied (inventory full check)
    if (IsSlotOccupied(indicatorSlot, tol)) {
        LogLine(LOG_FILE, "FishPhase: Inventory full (slot " indicatorSlot " occupied) - stopping")
        ShowTipFor("Fisher: Inventory full - stopping bot!", 5000)
        StopAndLog(runner, "Inventory full")
        return GoToPhase(runner, "fish")
    }

    fa := ctx["targetRegions"]["FishArea"]
    fishImg := ctx["images"]["FishImg"]
    imgW := CtxTunable(ctx, "fishImgWidth", 64)
    imgH := CtxTunable(ctx, "fishImgHeight", 48)

    ; 2. Search for the fishing spot
    if (!FindImageCenter(fa["x1"], fa["y1"], fa["x2"], fa["y2"], fishImg["file"], imgW, imgH, &cx, &cy, fishImg["options"])) {
        if (A_TickCount - lastSearchTipAt > 4000) {
            ShowTipFor("No fishing spot found in the calibrated area - still searching...", 1500)
            LogLine(LOG_FILE, "fish: no spot found in area, still searching")
            lastSearchTipAt := A_TickCount
        }
        return GoToPhase(runner, "fish")
    }

    LogLine(LOG_FILE, "fish: found spot at " cx "," cy " - clicking")
    HumanClick(cx, cy, 10, 10, ctx["runMode"])
    ResetPhaseTimer(runner)

    ; Settle delay
    settleMs := CtxTunable(ctx, "fishSettleMs", 600)
    Sleep(JitterDelay(settleMs))

    ; 3. Acquire Stage: Wait up to timeoutMs for the spot to be seen ANYWHERE in the area at least once (covers walk)
    acquired := false
    acquireTimeout := CtxTunable(ctx, "fishAcquireTimeoutMs", 10000)
    deadline := A_TickCount + acquireTimeout
    pollMs := CtxTunable(ctx, "fishPollMs", 150)

    loop {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "fish")
        if (IsSlotOccupied(indicatorSlot, tol)) {
            LogLine(LOG_FILE, "fish: inventory full (during acquire) - stopping")
            ShowTipFor("Fisher: Inventory full - stopping bot!", 5000)
            StopAndLog(runner, "Inventory full")
            return GoToPhase(runner, "fish")
        }
        if (FindImageCenter(fa["x1"], fa["y1"], fa["x2"], fa["y2"], fishImg["file"], imgW, imgH, &cx, &cy, fishImg["options"])) {
            acquired := true
            break
        }
        if (A_TickCount >= deadline)
            break
        Sleep(pollMs)
    }

    if (!acquired) {
        LogLine(LOG_FILE, "fish: never saw the spot again after clicking (acquire timeout) - re-searching")
        return GoToPhase(runner, "fish")
    }
    LogLine(LOG_FILE, "fish: acquired at " cx "," cy " - tracking")

    ; 4. Track Stage
    missingStreak := 0
    goneTicks := CtxTunable(ctx, "fishSpotGoneConfirmTicks", 5)
    radius := CtxTunable(ctx, "fishSpotRadius", 70)
    overallTimeout := CtxTunable(ctx, "fishTimeoutMs", 900000)
    trackDeadline := A_TickCount + overallTimeout

    loop {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "fish")
        if (IsSlotOccupied(indicatorSlot, tol)) {
            LogLine(LOG_FILE, "fish: inventory full (during tracking) - stopping")
            ShowTipFor("Fisher: Inventory full - stopping bot!", 5000)
            StopAndLog(runner, "Inventory full")
            return GoToPhase(runner, "fish")
        }

        x1 := cx - radius
        y1 := cy - radius
        x2 := cx + radius
        y2 := cy + radius

        if (FindImageCenter(x1, y1, x2, y2, fishImg["file"], imgW, imgH, &ncx, &ncy, fishImg["options"])) {
            cx := ncx
            cy := ncy
            missingStreak := 0
        } else {
            missingStreak += 1
            if (missingStreak >= goneTicks) {
                ResetPhaseTimer(runner)
                LogLine(LOG_FILE, "fish: spot confirmed gone after " missingStreak " misses (last seen near " cx "," cy ") - re-searching")
                return GoToPhase(runner, "fish")
            }
        }

        if (A_TickCount >= trackDeadline) {
            StopAndLog(runner, "Fishing timed out - spot never left and inventory never filled")
            return GoToPhase(runner, "fish")
        }
        Sleep(pollMs)
    }
}
