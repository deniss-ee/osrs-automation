; ============================================================
; auto-cooker.ahk - v3
;
; Cycle:
;   1. Search range-marker region for #FF00FF blob, click center
;   2. Run to range; wait for smelt-cook.png, press Space
;   3. Wait for indicator slot 28 to change (cooked)
;   4. Search bank-marker region for #0000FF blob, click center
;   5. Run to bank; wait for deposit.png, click Deposit All
;   6. Withdraw raw food from 1st bank slot, loop back to range
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
#Include ..\lib\Marker.ahk
#Include ..\lib\Walk.ahk
#Include ..\lib\Bank.ahk
#Include ..\lib\Validate.ahk
#Include ..\lib\TaskRunner.ahk
#Include ..\lib\Log.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

global CONFIG   := A_ScriptDir "\..\config\auto-cooker.ini"
global LOG_FILE := A_ScriptDir "\..\logs\auto-cooker-debug.log"
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
    
    ctx["runner"] := NewTaskRunner(150)
    AddPhase(ctx["runner"], "walkRange", WalkRangePhase, CtxTunable(ctx, "phaseTimeoutWalk", 60000))
    AddPhase(ctx["runner"], "cook",       CookPhase,       CtxTunable(ctx, "phaseTimeoutCook", 180000))
    AddPhase(ctx["runner"], "walkBank",   WalkBankPhase,   CtxTunable(ctx, "phaseTimeoutWalk", 60000))
    AddPhase(ctx["runner"], "bank",       BankPhase,       CtxTunable(ctx, "phaseTimeoutBank", 30000))
    
    StartTaskRunner(ctx["runner"], "walkRange")
    LogLine(LOG_FILE, "===== Cooker started =====")
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
; CONFIG LOAD
; ============================================================

LoadConfig() {
    global ctx, CONFIG

    ; Load Tunables & Save Back (always populate defaults if missing)
    ctx["tunables"]["colorTolerance"]        := DbGet(CONFIG, "Tunables", "colorTolerance",        20,     "int")
    ctx["tunables"]["indicatorSlot"]         := DbGet(CONFIG, "Tunables", "indicatorSlot",         28,     "int")
    ctx["tunables"]["cookSettleMs"]          := DbGet(CONFIG, "Tunables", "cookSettleMs",          600,    "int")
    ctx["tunables"]["cookTimeoutMs"]         := DbGet(CONFIG, "Tunables", "cookTimeoutMs",         120000, "int")
    ctx["tunables"]["spaceKeySettleMs"]      := DbGet(CONFIG, "Tunables", "spaceKeySettleMs",      200,    "int")
    ctx["tunables"]["markerSearchTimeoutMs"] := DbGet(CONFIG, "Tunables", "markerSearchTimeoutMs", 5000,  "int")
    ctx["tunables"]["walkTimeoutMs"]         := DbGet(CONFIG, "Tunables", "walkTimeoutMs",         30000,  "int")
    ctx["tunables"]["bankSettleMs"]          := DbGet(CONFIG, "Tunables", "bankSettleMs",          300,    "int")
    ctx["tunables"]["bankFailsafeMs"]        := DbGet(CONFIG, "Tunables", "bankFailsafeMs",        300,    "int")
    ctx["tunables"]["withdrawInterSettleMs"] := DbGet(CONFIG, "Tunables", "withdrawInterSettleMs", 600,    "int")
    ctx["tunables"]["withdrawFinalSettleMs"] := DbGet(CONFIG, "Tunables", "withdrawFinalSettleMs", 300,    "int")
    ctx["tunables"]["phaseTimeoutWalk"]      := DbGet(CONFIG, "Tunables", "phaseTimeoutWalk",      60000,  "int")
    ctx["tunables"]["phaseTimeoutCook"]      := DbGet(CONFIG, "Tunables", "phaseTimeoutCook",      180000, "int")
    ctx["tunables"]["phaseTimeoutBank"]      := DbGet(CONFIG, "Tunables", "phaseTimeoutBank",      30000,  "int")

    DbSet(CONFIG, "Tunables", "colorTolerance",        ctx["tunables"]["colorTolerance"],        "int")
    DbSet(CONFIG, "Tunables", "indicatorSlot",         ctx["tunables"]["indicatorSlot"],         "int")
    DbSet(CONFIG, "Tunables", "cookSettleMs",          ctx["tunables"]["cookSettleMs"],          "int")
    DbSet(CONFIG, "Tunables", "cookTimeoutMs",         ctx["tunables"]["cookTimeoutMs"],         "int")
    DbSet(CONFIG, "Tunables", "spaceKeySettleMs",      ctx["tunables"]["spaceKeySettleMs"],      "int")
    DbSet(CONFIG, "Tunables", "markerSearchTimeoutMs", ctx["tunables"]["markerSearchTimeoutMs"], "int")
    DbSet(CONFIG, "Tunables", "walkTimeoutMs",         ctx["tunables"]["walkTimeoutMs"],         "int")
    DbSet(CONFIG, "Tunables", "bankSettleMs",          ctx["tunables"]["bankSettleMs"],          "int")
    DbSet(CONFIG, "Tunables", "bankFailsafeMs",        ctx["tunables"]["bankFailsafeMs"],        "int")
    DbSet(CONFIG, "Tunables", "withdrawInterSettleMs", ctx["tunables"]["withdrawInterSettleMs"], "int")
    DbSet(CONFIG, "Tunables", "withdrawFinalSettleMs", ctx["tunables"]["withdrawFinalSettleMs"], "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutWalk",      ctx["tunables"]["phaseTimeoutWalk"],      "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutCook",      ctx["tunables"]["phaseTimeoutCook"],      "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutBank",      ctx["tunables"]["phaseTimeoutBank"],      "int")

    ; Load Markers (write back defaults if missing so they appear in the INI)
    rmColor := DbGet(CONFIG, "RangeMarker", "color", 0xFF00FF, "color")
    rmTol := DbGet(CONFIG, "RangeMarker", "tolerance", 5, "int")
    rmX1 := DbGet(CONFIG, "RangeMarker", "x1", 1293, "int")
    rmY1 := DbGet(CONFIG, "RangeMarker", "y1", 572, "int")
    rmX2 := DbGet(CONFIG, "RangeMarker", "x2", 1309, "int")
    rmY2 := DbGet(CONFIG, "RangeMarker", "y2", 588, "int")
    rmOffsetX := DbGet(CONFIG, "RangeMarker", "clickOffsetX", 0, "int")
    rmOffsetY := DbGet(CONFIG, "RangeMarker", "clickOffsetY", 0, "int")
    DbSetMarker(CONFIG, "RangeMarker", rmColor, rmTol, rmX1, rmY1, rmX2, rmY2, rmOffsetX, rmOffsetY)
    ctx["markers"]["RangeWalkMarker"] := Map("color", rmColor, "tolerance", rmTol, "x1", rmX1, "y1", rmY1, "x2", rmX2, "y2", rmY2, "clickOffsetX", rmOffsetX, "clickOffsetY", rmOffsetY)

    bmColor := DbGet(CONFIG, "BankMarker", "color", 0x0000FF, "color")
    bmTol := DbGet(CONFIG, "BankMarker", "tolerance", 5, "int")
    bmX1 := DbGet(CONFIG, "BankMarker", "x1", 563, "int")
    bmY1 := DbGet(CONFIG, "BankMarker", "y1", 948, "int")
    bmX2 := DbGet(CONFIG, "BankMarker", "x2", 595, "int")
    bmY2 := DbGet(CONFIG, "BankMarker", "y2", 980, "int")
    bmOffsetX := DbGet(CONFIG, "BankMarker", "clickOffsetX", 0, "int")
    bmOffsetY := DbGet(CONFIG, "BankMarker", "clickOffsetY", 0, "int")
    DbSetMarker(CONFIG, "BankMarker", bmColor, bmTol, bmX1, bmY1, bmX2, bmY2, bmOffsetX, bmOffsetY)
    ctx["markers"]["BankWalkMarker"] := Map("color", bmColor, "tolerance", bmTol, "x1", bmX1, "y1", bmY1, "x2", bmX2, "y2", bmY2, "clickOffsetX", bmOffsetX, "clickOffsetY", bmOffsetY)

    ; Load Images (write back defaults if missing so they appear in the INI)
    scFile := DbGet(CONFIG, "SmeltCookImg", "file", "..\images\smelt-cook.png", "str")
    scW := DbGet(CONFIG, "SmeltCookImg", "w", 50, "int")
    scH := DbGet(CONFIG, "SmeltCookImg", "h", 50, "int")
    scOpt := DbGet(CONFIG, "SmeltCookImg", "options", "*20", "str")
    scX1 := DbGet(CONFIG, "SmeltCookImg", "x1", 0, "int")
    scY1 := DbGet(CONFIG, "SmeltCookImg", "y1", 0, "int")
    scX2 := DbGet(CONFIG, "SmeltCookImg", "x2", 1600, "int")
    scY2 := DbGet(CONFIG, "SmeltCookImg", "y2", 1200, "int")
    DbSetImage(CONFIG, "SmeltCookImg", scFile, scW, scH, scOpt, scX1, scY1, scX2, scY2)
    ctx["images"]["SmeltCookImg"] := Map("file", scFile, "w", scW, "h", scH, "options", scOpt, "x1", scX1, "y1", scY1, "x2", scX2, "y2", scY2)

    depFile := DbGet(CONFIG, "DepositImg", "file", "..\images\deposit.png", "str")
    depW := DbGet(CONFIG, "DepositImg", "w", 72, "int")
    depH := DbGet(CONFIG, "DepositImg", "h", 72, "int")
    depOpt := DbGet(CONFIG, "DepositImg", "options", "*20", "str")
    depX1 := DbGet(CONFIG, "DepositImg", "x1", 0, "int")
    depY1 := DbGet(CONFIG, "DepositImg", "y1", 0, "int")
    depX2 := DbGet(CONFIG, "DepositImg", "x2", 1600, "int")
    depY2 := DbGet(CONFIG, "DepositImg", "y2", 1200, "int")
    DbSetImage(CONFIG, "DepositImg", depFile, depW, depH, depOpt, depX1, depY1, depX2, depY2)
    ctx["images"]["DepositImg"] := Map("file", depFile, "w", depW, "h", depH, "options", depOpt, "x1", depX1, "y1", depY1, "x2", depX2, "y2", depY2)

    ; Load Settings
    ctx["runMode"] := DbGet(CONFIG, "Settings", "runMode", false, "bool")
    DbSet(CONFIG, "Settings", "runMode", ctx["runMode"], "bool")

    ; Load Withdraw Plan (write back user's requested defaults if missing so they appear in the INI)
    plan := DbGetWithdrawPlan(CONFIG, "WithdrawPlan:Default")
    if (plan.Length = 0) {
        plan := [
            Map("slot", 1, "count", 1),
            Map("slot", 2, "count", 2),
            Map("slot", 3, "count", 1)
        ]
        DbSetWithdrawPlan(CONFIG, "WithdrawPlan:Default", plan)
    }
    ctx["withdrawPlans"]["Default"] := plan
}

; ============================================================
; SETUP VALIDATION
; ============================================================

ValidateSetup() {
    global ctx
    v := NewValidator()

    rm := CtxMarker(ctx, "RangeWalkMarker")
    bm := CtxMarker(ctx, "BankWalkMarker")
    RequireRegion(v, "RangeWalkMarker region", rm["x1"], rm["y1"], rm["x2"], rm["y2"])
    RequireColor(v, "RangeWalkMarker color", rm["color"])
    RequireRegion(v, "BankWalkMarker region", bm["x1"], bm["y1"], bm["x2"], bm["y2"])
    RequireColor(v, "BankWalkMarker color", bm["color"])

    smeltImg := CtxImage(ctx, "SmeltCookImg")
    depositImg := CtxImage(ctx, "DepositImg")
    RequireFile(v, "smelt-cook.png image", smeltImg["file"])
    RequireFile(v, "deposit.png image", depositImg["file"])

    return ShowValidationErrors(v)
}

; ============================================================
; PHASES
; ============================================================

; Phase 1: Search range-marker region for pink, click it, wait for smelt-cook.png
WalkRangePhase(runner) {
    global ctx, LOG_FILE
    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "walkRange")

    ShowTip("Cooker: searching range marker...")

    rm := CtxMarker(ctx, "RangeWalkMarker")
    if (!WaitForPixelSearch(ctx, &rx, &ry, rm["x1"], rm["y1"], rm["x2"], rm["y2"], rm["color"], rm["tolerance"], CtxTunable(ctx, "markerSearchTimeoutMs", 5000))) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "walkRange")
        LogLine(LOG_FILE, "WalkRange: marker not found - retrying")
        ShowTipFor("Cooker: range marker not found - retrying", 2000)
        return GoToPhase(runner, "walkRange")
    }

    cx := rm["x1"] + (rm["x2"] - rm["x1"]) // 2
    cy := rm["y1"] + (rm["y2"] - rm["y1"]) // 2
    HumanClick(cx + rm["clickOffsetX"], cy + rm["clickOffsetY"], 0, 0, ctx["runMode"])
    ResetPhaseTimer(ctx["runner"])
    ShowTip("Cooker: walking to range...")

    smeltImg := CtxImage(ctx, "SmeltCookImg")
    if (!WaitForImageCenter(ctx, smeltImg["x1"], smeltImg["y1"], smeltImg["x2"], smeltImg["y2"],
                            smeltImg["file"], smeltImg["w"], smeltImg["h"], &_cx, &_cy,
                            CtxTunable(ctx, "walkTimeoutMs", 30000),
                            smeltImg.Has("options") ? smeltImg["options"] : "")) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "walkRange")
        LogLine(LOG_FILE, "WalkRange: never arrived at range - retrying")
        ShowTipFor("Cooker: never arrived at range - retrying", 2000)
        return GoToPhase(runner, "walkRange")
    }

    LogLine(LOG_FILE, "WalkRange: arrived at range")
    ShowTipFor("Cooker: arrived at range", 1500)
    return GoToPhase(runner, "cook")
}

; Phase 2: Wait for smelt-cook.png, press Space, wait for slot 28 to change (item cooked)
CookPhase(runner) {
    global ctx, LOG_FILE
    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "cook")

    smeltImg := CtxImage(ctx, "SmeltCookImg")
    tol := CtxTunable(ctx, "colorTolerance", 20)

    if (!IsImagePresent(smeltImg["x1"], smeltImg["y1"], smeltImg["x2"], smeltImg["y2"], smeltImg["file"],
                        smeltImg.Has("options") ? smeltImg["options"] : "")) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "walkRange")
        LogLine(LOG_FILE, "CookPhase: smelt-cook dialog not visible - re-walking")
        ShowTipFor("Cooker: no cook dialog - re-walking to range", 2000)
        return GoToPhase(runner, "walkRange")
    }

    indicatorSlot := CtxTunable(ctx, "indicatorSlot", 28)
    cookTimeoutMs := CtxTunable(ctx, "cookTimeoutMs", 120000)

    ; Capture baseline signature BEFORE pressing Space to detect when the raw food item changes/disappears
    presmeltSig := CalibrateSlotSignature(indicatorSlot)

    ShowTip("Cooker: cooking...")
    HumanKeyPress("Space")
    ResetPhaseTimer(ctx["runner"])
    Sleep(JitterDelay(CtxTunable(ctx, "spaceKeySettleMs", 200)))

    ; Wait for indicator slot 28 to change (item cooked)
    done := WaitForSlotChange(ctx, presmeltSig, tol, cookTimeoutMs)

    if (!done) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "cook")
        LogLine(LOG_FILE, "CookPhase: indicator slot never changed within timeout")
        StopAndLog(ctx["runner"], "Cooking timed out - stopped")
        return GoToPhase(runner, "cook")
    }

    LogLine(LOG_FILE, "CookPhase: cooking complete")
    ShowTipFor("Cooker: cooking done", 1500)
    return GoToPhase(runner, "walkBank")
}

; Phase 3: Search bank-marker region for blue, click it, wait for deposit.png
WalkBankPhase(runner) {
    global ctx, LOG_FILE
    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "walkBank")

    ShowTip("Cooker: searching bank marker...")

    bm := CtxMarker(ctx, "BankWalkMarker")
    if (!WaitForPixelSearch(ctx, &bx, &by, bm["x1"], bm["y1"], bm["x2"], bm["y2"], bm["color"], bm["tolerance"], CtxTunable(ctx, "markerSearchTimeoutMs", 5000))) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "walkBank")
        LogLine(LOG_FILE, "WalkBank: marker not found - retrying")
        ShowTipFor("Cooker: bank marker not found - retrying", 2000)
        return GoToPhase(runner, "walkBank")
    }

    cx := bm["x1"] + (bm["x2"] - bm["x1"]) // 2
    cy := bm["y1"] + (bm["y2"] - bm["y1"]) // 2
    HumanClick(cx + bm["clickOffsetX"], cy + bm["clickOffsetY"], 0, 0, ctx["runMode"])
    ResetPhaseTimer(ctx["runner"])
    ShowTip("Cooker: walking to bank...")

    depositImg := CtxImage(ctx, "DepositImg")
    if (!WaitForImageCenter(ctx, depositImg["x1"], depositImg["y1"], depositImg["x2"], depositImg["y2"],
                            depositImg["file"], depositImg["w"], depositImg["h"], &_cx, &_cy,
                            CtxTunable(ctx, "walkTimeoutMs", 30000),
                            depositImg.Has("options") ? depositImg["options"] : "")) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "walkBank")
        LogLine(LOG_FILE, "WalkBank: never arrived at bank - retrying")
        ShowTipFor("Cooker: never arrived at bank - retrying", 2000)
        return GoToPhase(runner, "walkBank")
    }

    LogLine(LOG_FILE, "WalkBank: arrived at bank")
    ShowTipFor("Cooker: arrived at bank", 1500)
    return GoToPhase(runner, "bank")
}

; Phase 4: deposit all cooked items, withdraw slot 1 once, loop back to range
BankPhase(runner) {
    global ctx, LOG_FILE
    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "bank")

    ShowTip("Cooker: banking...")

    depositImg := CtxImage(ctx, "DepositImg")

    if (!BankDepositAll(ctx, depositImg["file"], CtxTunable(ctx, "bankSettleMs", 300),
                        CtxTunable(ctx, "bankFailsafeMs", 300))) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "bank")
        LogLine(LOG_FILE, "BankPhase: deposit failed - bank may not be open")
        ShowTipFor("Cooker: deposit failed - retrying bank", 2000)
        return GoToPhase(runner, "bank")
    }

    ; Withdraw per plan
    plan := CtxWithdrawPlan(ctx, "Default")
    if (plan.Length > 0) {
        BankWithdrawPlan(plan, CtxTunable(ctx, "withdrawInterSettleMs", 600),
                               CtxTunable(ctx, "withdrawFinalSettleMs", 300))
    }

    LogLine(LOG_FILE, "BankPhase: deposited and withdrew supplies, cycling back to range")
    ShowTipFor("Cooker: bank done - heading to range", 1500)
    return GoToPhase(runner, "walkRange")
}
