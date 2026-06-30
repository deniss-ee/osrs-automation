; ============================================================
; auto-miner.ahk - v3
;
; Cycle:
;   1. Stand near ore veins. Wait/search configured regions for `#FF00FF` blob.
;      If one is found, click its centroid and start mining (make it the active vein).
;   2. Monitor active vein region. Keep mining until `#FF00FF` is depleted.
;      Do not switch veins while mining is in progress.
;   3. When indicator slot (default 28) is full, search bank marker region for
;      `#FF00FF` blob, click its centroid.
;   4. Wait for deposit button image to appear, then click deposit button.
;   5. After deposit is confirmed (slot 28 empty), click the return walk point on
;      the minimap (default x=1453 y=929), and walk back to the veins.
;
; No calibration hotkeys. Coordinates are populated directly into configuration.
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
#Include ..\lib\Bank.ahk
#Include ..\lib\Validate.ahk
#Include ..\lib\TaskRunner.ahk
#Include ..\lib\Log.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

global CONFIG   := A_ScriptDir "\..\config\auto-miner.ini"
global LOG_FILE := A_ScriptDir "\..\logs\auto-miner-debug.log"
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
    
    ctx["runner"] := NewTaskRunner(50)
    AddPhase(ctx["runner"], "mine",      MinePhase,      CtxTunable(ctx, "phaseTimeoutMine",  180000))
    AddPhase(ctx["runner"], "walkBank",  WalkBankPhase,  CtxTunable(ctx, "phaseTimeoutWalk",   60000))
    AddPhase(ctx["runner"], "bank",      BankPhase,      CtxTunable(ctx, "phaseTimeoutBank",   30000))
    AddPhase(ctx["runner"], "walkVeins", WalkVeinsPhase, CtxTunable(ctx, "phaseTimeoutWalk",   60000))

    ctx["activeVein"] := 0  ; Track currently mined vein index (0 = none)
    StartTaskRunner(ctx["runner"], "mine")
    TickTaskRunner(ctx["runner"]) ; Force first tick instantly!
    LogLine(LOG_FILE, "===== Miner started =====")
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

; Phase 1: mine active vein or search for next active vein
MinePhase(runner) {
    global ctx, LOG_FILE
    static lastLogTime := 0

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
    activeVein := ctx.Has("activeVein") ? ctx["activeVein"] : 0
    veinCount  := CtxTunable(ctx, "veinCount", 2)

    if (A_TickCount - lastLogTime > 2000) {
        lastLogTime := A_TickCount
        LogLine(LOG_FILE, "MinePhase tick: ACTIVE, slot28Occupied=" (slotOccupied ? "true" : "false") " activeVein=" activeVein)
    }

    ; 1. Check if inventory slot 28 is full
    if (slotOccupied) {
        LogLine(LOG_FILE, "MinePhase: inventory full (slot " indicatorSlot " occupied) - banking")
        ShowTipFor("Miner: inventory full - going to bank", 1500)
        return GoToPhase(runner, "walkBank")
    }

    ; 2. If we are currently mining a vein, verify it is still active
    if (activeVein > 0) {
        vm := ctx["markers"]["Vein" activeVein]
        ; Check if the vein marker color is still present in the region
        if (IsColorInRegion(vm["x1"], vm["y1"], vm["x2"], vm["y2"], vm["color"], vm["tolerance"])) {
            ; Still mining, do nothing and loop
            ShowTip("Miner: mining Vein " activeVein "...")
            return GoToPhase(runner, "mine")
        } else {
            ; Vein is empty/depleted!
            LogLine(LOG_FILE, "MinePhase: Vein " activeVein " depleted")
            ctx["activeVein"] := 0
            activeVein := 0
        }
    }

    ; 3. If no active vein, look for another vein that has the marker color
    loop veinCount {
        i := A_Index
        vm := ctx["markers"]["Vein" i]
        found := IsColorInRegion(vm["x1"], vm["y1"], vm["x2"], vm["y2"], vm["color"], vm["tolerance"])
        if (A_TickCount - lastLogTime > 1900) {
            LogLine(LOG_FILE, "  Checking Vein " i ": found=" (found ? "true" : "false") " region=[" vm["x1"] "," vm["y1"] " to " vm["x2"] "," vm["y2"] "]")
        }
        if (found) {
            ; Click the center of the vein to start mining
            vx := vm["x1"] + (vm["x2"] - vm["x1"]) // 2
            vy := vm["y1"] + (vm["y2"] - vm["y1"]) // 2
            HumanClick(vx, vy, 0, 0, ctx["runMode"])
            ctx["activeVein"] := i
            ResetPhaseTimer(ctx["runner"])
            LogLine(LOG_FILE, "MinePhase: clicked Vein " i)
            ShowTipFor("Miner: started mining Vein " i, 1500)
            return GoToPhase(runner, "mine")
        }
    }

    ; 4. If no vein is active, wait
    ShowTip("Miner: waiting for veins...")
    return GoToPhase(runner, "mine")
}

; Phase 2: find first color pixel in bank region, click it, wait for deposit.png
WalkBankPhase(runner) {
    global ctx, LOG_FILE
    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "walkBank")

    ShowTip("Miner: searching bank marker...")

    bm := ctx["markers"]["BankMarker"]
    if (!IsColorInRegion(bm["x1"], bm["y1"], bm["x2"], bm["y2"], bm["color"], bm["tolerance"])) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "walkBank")
        return GoToPhase(runner, "walkBank")
    }

    ; Click the center of the bank region instantly
    bx := bm["x1"] + (bm["x2"] - bm["x1"]) // 2
    by := bm["y1"] + (bm["y2"] - bm["y1"]) // 2
    HumanClick(bx, by, 0, 0, ctx["runMode"])
    ResetPhaseTimer(ctx["runner"])
    ShowTip("Miner: walking to bank...")

    depositImg := ctx["images"]["DepositImg"]
    if (!WaitForImageCenter(ctx, depositImg["x1"], depositImg["y1"], depositImg["x2"], depositImg["y2"],
                            depositImg["file"], depositImg["w"], depositImg["h"], &_cx, &_cy,
                            CtxTunable(ctx, "walkTimeoutMs", 30000),
                            depositImg.Has("options") ? depositImg["options"] : "",
                            50)) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "walkBank")
        LogLine(LOG_FILE, "WalkBank: never arrived at bank - retrying")
        ShowTipFor("Miner: never arrived at bank - retrying", 2000)
        return GoToPhase(runner, "walkBank")
    }

    LogLine(LOG_FILE, "WalkBank: arrived at bank")
    ShowTipFor("Miner: arrived at bank", 1500)
    return GoToPhase(runner, "bank")
}

; Phase 3: deposit all, click returnWalkPoint, transition to walkVeins
BankPhase(runner) {
    global ctx, LOG_FILE
    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "bank")

    ShowTip("Miner: banking...")

    depositImg := ctx["images"]["DepositImg"]

    if (!BankDepositAll(ctx, depositImg["file"], CtxTunable(ctx, "bankSettleMs", 100),
                        CtxTunable(ctx, "bankFailsafeMs", 100))) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "bank")
        LogLine(LOG_FILE, "BankPhase: deposit failed - bank may not be open")
        ShowTipFor("Miner: deposit failed - retrying bank", 2000)
        return GoToPhase(runner, "bank")
    }

    ; After deposit is done, click returnWalkPoint once immediately
    pt := ctx["returnWalkPoint"]
    HumanClick(pt["x"], pt["y"], 0, 0, ctx["runMode"])
    ResetPhaseTimer(ctx["runner"])

    LogLine(LOG_FILE, "BankPhase: deposited and clicked walk-back, cycling to walkVeins")
    ShowTipFor("Miner: bank done - heading to veins", 1500)
    return GoToPhase(runner, "walkVeins")
}

; Phase 4: wait/walk back until one of the veins is visible and clickable
WalkVeinsPhase(runner) {
    global ctx, LOG_FILE
    static lastLogTime := 0

    if (!RequireOsrsWindowActive(ctx)) {
        if (A_TickCount - lastLogTime > 2000) {
            lastLogTime := A_TickCount
            LogLine(LOG_FILE, "WalkVeinsPhase tick: PAUSED (RuneLite not focused)")
        }
        return GoToPhase(runner, "walkVeins")
    }

    if (A_TickCount - lastLogTime > 2000) {
        lastLogTime := A_TickCount
        LogLine(LOG_FILE, "WalkVeinsPhase tick: ACTIVE")
    }

    ShowTip("Miner: walking and waiting for veins to appear...")

    veinCount := CtxTunable(ctx, "veinCount", 2)
    loop veinCount {
        i := A_Index
        vm := ctx["markers"]["Vein" i]
        found := IsColorInRegion(vm["x1"], vm["y1"], vm["x2"], vm["y2"], vm["color"], vm["tolerance"])
        if (A_TickCount - lastLogTime > 1900) {
            LogLine(LOG_FILE, "  Checking Vein " i ": found=" (found ? "true" : "false"))
        }
        if (found) {
            ; Wait a brief settle time only once after walking back
            Sleep(JitterDelay(CtxTunable(ctx, "walkBackSettleMs", 300)))
            ; Click the active vein center!
            vx := vm["x1"] + (vm["x2"] - vm["x1"]) // 2
            vy := vm["y1"] + (vm["y2"] - vm["y1"]) // 2
            HumanClick(vx, vy, 0, 0, ctx["runMode"])
            ctx["activeVein"] := i
            ResetPhaseTimer(ctx["runner"])
            LogLine(LOG_FILE, "WalkVeinsPhase: clicked Vein " i)
            ShowTipFor("Miner: started mining Vein " i, 1500)
            return GoToPhase(runner, "mine")
        }
    }

    ; Not yet visible, keep waiting
    return GoToPhase(runner, "walkVeins")
}

; ============================================================
; CONFIG
; ============================================================

LoadConfig() {
    global ctx, CONFIG

    ; --- Tunables (read from ini or write defaults) ---
    ctx["tunables"]["colorTolerance"]        := DbGet(CONFIG, "Tunables", "colorTolerance",        20,     "int")
    ctx["tunables"]["markerSearchTimeoutMs"] := DbGet(CONFIG, "Tunables", "markerSearchTimeoutMs", 5000,   "int")
    ctx["tunables"]["walkTimeoutMs"]         := DbGet(CONFIG, "Tunables", "walkTimeoutMs",         30000,  "int")
    ctx["tunables"]["bankTimeoutMs"]         := DbGet(CONFIG, "Tunables", "bankTimeoutMs",         5000,   "int")
    ctx["tunables"]["bankSettleMs"]          := DbGet(CONFIG, "Tunables", "bankSettleMs",          100,    "int")
    ctx["tunables"]["bankFailsafeMs"]        := DbGet(CONFIG, "Tunables", "bankFailsafeMs",        100,    "int")
    ctx["tunables"]["walkBackSettleMs"]      := DbGet(CONFIG, "Tunables", "walkBackSettleMs",      300,    "int")
    ctx["tunables"]["phaseTimeoutMine"]      := DbGet(CONFIG, "Tunables", "phaseTimeoutMine",      180000, "int")
    ctx["tunables"]["phaseTimeoutWalk"]      := DbGet(CONFIG, "Tunables", "phaseTimeoutWalk",      60000,  "int")
    ctx["tunables"]["phaseTimeoutBank"]      := DbGet(CONFIG, "Tunables", "phaseTimeoutBank",      30000,  "int")
    ctx["tunables"]["veinCount"]             := DbGet(CONFIG, "Settings", "veinCount",             2,      "int")
    ctx["tunables"]["indicatorSlot"]         := DbGet(CONFIG, "Settings", "indicatorSlot",         28,     "int")

    ; Write all tunables/settings back to ini so they appear in the file
    DbSet(CONFIG, "Tunables", "colorTolerance",        ctx["tunables"]["colorTolerance"],        "int")
    DbSet(CONFIG, "Tunables", "markerSearchTimeoutMs", ctx["tunables"]["markerSearchTimeoutMs"], "int")
    DbSet(CONFIG, "Tunables", "walkTimeoutMs",         ctx["tunables"]["walkTimeoutMs"],         "int")
    DbSet(CONFIG, "Tunables", "bankTimeoutMs",         ctx["tunables"]["bankTimeoutMs"],         "int")
    DbSet(CONFIG, "Tunables", "bankSettleMs",          ctx["tunables"]["bankSettleMs"],          "int")
    DbSet(CONFIG, "Tunables", "bankFailsafeMs",        ctx["tunables"]["bankFailsafeMs"],        "int")
    DbSet(CONFIG, "Tunables", "walkBackSettleMs",      ctx["tunables"]["walkBackSettleMs"],      "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutMine",      ctx["tunables"]["phaseTimeoutMine"],      "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutWalk",      ctx["tunables"]["phaseTimeoutWalk"],      "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutBank",      ctx["tunables"]["phaseTimeoutBank"],      "int")

    ; --- Settings ---
    ctx["runMode"] := DbGet(CONFIG, "Settings", "runMode", true, "bool")
    DbSet(CONFIG, "Settings", "runMode", ctx["runMode"], "bool")
    
    DbSet(CONFIG, "Settings", "veinCount",             ctx["tunables"]["veinCount"],             "int")
    DbSet(CONFIG, "Settings", "indicatorSlot",         ctx["tunables"]["indicatorSlot"],         "int")

    ; --- Return Walk Point ---
    ctx["returnWalkPoint"] := DbGetPoint(CONFIG, "Settings", "returnWalkPoint", 1453, 929)
    if (ctx["returnWalkPoint"]["x"] = 0 && ctx["returnWalkPoint"]["y"] = 0) {
        DbSetPoint(CONFIG, "Settings", "returnWalkPoint", 1453, 929)
        ctx["returnWalkPoint"] := DbGetPoint(CONFIG, "Settings", "returnWalkPoint", 1453, 929)
    }

    ; --- Vein markers ---
    veinCount := ctx["tunables"]["veinCount"]
    loop veinCount {
        i := A_Index
        ctx["markers"]["Vein" i] := DbGetMarker(CONFIG, "Marker:Vein" i)
        if (ctx["markers"]["Vein" i]["color"] = -1) {
            if (i = 1)
                DbSetMarker(CONFIG, "Marker:Vein1", 0xFF00FF, 20, 919, 706, 951, 738, 0, 0)
            else if (i = 2)
                DbSetMarker(CONFIG, "Marker:Vein2", 0xFF00FF, 20, 993, 772, 1025, 804, 0, 0)
            else
                DbSetMarker(CONFIG, "Marker:Vein" i, 0xFF00FF, 20, 0, 0, 0, 0, 0, 0)
            ctx["markers"]["Vein" i] := DbGetMarker(CONFIG, "Marker:Vein" i)
        }
    }

    ; --- Bank marker ---
    ctx["markers"]["BankMarker"] := DbGetMarker(CONFIG, "Marker:BankMarker")
    if (ctx["markers"]["BankMarker"]["color"] = -1) {
        DbSetMarker(CONFIG, "Marker:BankMarker", 0xFF00FF, 20, 519, 524, 551, 556, 0, 0)
        ctx["markers"]["BankMarker"] := DbGetMarker(CONFIG, "Marker:BankMarker")
    }

    ; --- Deposit image ---
    ctx["images"]["DepositImg"] := GetDepositButtonImage()
}

ValidateSetup() {
    global ctx
    v := NewValidator()

    veinCount := CtxTunable(ctx, "veinCount", 2)
    loop veinCount {
        i := A_Index
        vm := ctx["markers"]["Vein" i]
        RequireRegion(v, "Vein " i " marker region", vm["x1"], vm["y1"], vm["x2"], vm["y2"])
    }

    bm := ctx["markers"]["BankMarker"]
    RequireRegion(v, "Bank marker region", bm["x1"], bm["y1"], bm["x2"], bm["y2"])

    RequireFile(v, "Deposit button image", ctx["images"]["DepositImg"]["file"])

    pt := ctx["returnWalkPoint"]
    if (pt["x"] = 0 && pt["y"] = 0)
        v["errors"].Push("Return walk point is not calibrated (must be non-zero)")

    return ShowValidationErrors(v)
}
