; ============================================================
; auto-smelter.ahk - v3
;
; Cycle:
;   1. Search furnace-marker region for #FF00FF blob, click center
;   2. Run to furnace; wait for smelt-cook.png, press Space
;   3. Wait for indicator slot to empty (all ore consumed)
;   4. Search bank-marker region for #0000FF blob, click center
;   5. Run to bank; wait for deposit.png, click Deposit All
;   6. Execute withdraw plan, loop
;
; Hardcoded colors come from the user's fixed RuneLite layout.
; No calibration hotkeys needed for walk markers - colors are constant.
; Calibrate only: indicator slot (F1), withdraw plan (hardcoded in ini).
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

global CONFIG   := A_ScriptDir "\..\config\auto-smelter.ini"
global LOG_FILE := A_ScriptDir "\..\logs\auto-smelter-debug.log"
global ctx      := NewBotContext(CONFIG)

EnsureDbVersion(CONFIG)
LoadConfig()

; ============================================================
; HOTKEYS
; ============================================================

; F1 - calibrate the indicator slot (the slot that goes empty when smelting finishes)
F1:: CalibrateIndicatorSlot()
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
    AddPhase(ctx["runner"], "walkFurnace",  WalkFurnacePhase,  CtxTunable(ctx, "phaseTimeoutWalk",   60000))
    AddPhase(ctx["runner"], "smelt",        SmeltPhase,        CtxTunable(ctx, "phaseTimeoutSmelt", 180000))
    AddPhase(ctx["runner"], "walkBank",     WalkBankPhase,     CtxTunable(ctx, "phaseTimeoutWalk",   60000))
    AddPhase(ctx["runner"], "bank",         BankPhase,         CtxTunable(ctx, "phaseTimeoutBank",   30000))
    StartTaskRunner(ctx["runner"], "walkFurnace")
    LogLine(LOG_FILE, "===== Smelter started =====")
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

; Phase 1: find first #FF00FF pixel in furnace region, click it, wait for smelt-cook.png
WalkFurnacePhase(runner) {
    global ctx
    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "walkFurnace")

    ShowTip("Smelter: searching furnace marker...")

    fm := CtxMarker(ctx, "FurnaceWalkMarker")
    if (!WaitForPixelSearch(ctx, &fx, &fy, fm["x1"], fm["y1"], fm["x2"], fm["y2"], fm["color"], fm["tolerance"], CtxTunable(ctx, "markerSearchTimeoutMs", 5000))) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "walkFurnace")
        LogLine(LOG_FILE, "WalkFurnace: marker not found - retrying")
        ShowTipFor("Smelter: furnace marker not found - retrying", 2000)
        return GoToPhase(runner, "walkFurnace")
    }

    HumanClick(fx + fm["clickOffsetX"], fy + fm["clickOffsetY"], 0, 0, ctx["runMode"])
    ResetPhaseTimer(ctx["runner"])
    ShowTip("Smelter: walking to furnace...")

    smeltImg := CtxImage(ctx, "SmeltCookImg")
    if (!WaitForImageCenter(ctx, smeltImg["x1"], smeltImg["y1"], smeltImg["x2"], smeltImg["y2"],
                            smeltImg["file"], smeltImg["w"], smeltImg["h"], &_cx, &_cy,
                            CtxTunable(ctx, "walkTimeoutMs", 30000),
                            smeltImg.Has("options") ? smeltImg["options"] : "")) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "walkFurnace")
        LogLine(LOG_FILE, "WalkFurnace: never arrived at furnace - retrying")
        ShowTipFor("Smelter: never arrived at furnace - retrying", 2000)
        return GoToPhase(runner, "walkFurnace")
    }

    LogLine(LOG_FILE, "WalkFurnace: arrived at furnace")
    ShowTipFor("Smelter: arrived at furnace", 1500)
    return GoToPhase(runner, "smelt")
}

; Phase 2: smelt-cook.png is visible, press Space, wait for indicator slot to empty
SmeltPhase(runner) {
    global ctx
    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "smelt")

    smeltImg := CtxImage(ctx, "SmeltCookImg")
    tol := CtxTunable(ctx, "colorTolerance", 20)

    ; If smelt dialog not visible, go back to walk (e.g. already smelted, or walked past)
    if (!IsImagePresent(smeltImg["x1"], smeltImg["y1"], smeltImg["x2"], smeltImg["y2"], smeltImg["file"],
                        smeltImg.Has("options") ? smeltImg["options"] : "")) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "walkFurnace")
        LogLine(LOG_FILE, "SmeltPhase: smelt-cook dialog not visible - re-walking")
        ShowTipFor("Smelter: no smelt dialog - re-walking to furnace", 2000)
        return GoToPhase(runner, "walkFurnace")
    }

    indicatorSlot := CtxTunable(ctx, "indicatorSlot", 28)
    smeltTimeoutMs := CtxTunable(ctx, "smeltTimeoutMs", 120000)
    waitMode      := CtxTunable(ctx, "smeltWaitMode", "empty")

    ; Capture baseline BEFORE pressing Space so we can detect item change (ore→bar)
    if (waitMode = "change")
        presmeltSig := CalibrateSlotSignature(indicatorSlot)

    ShowTip("Smelter: smelting...")
    HumanKeyPress("Space")
    ResetPhaseTimer(ctx["runner"])
    Sleep(JitterDelay(CtxTunable(ctx, "spaceKeySettleMs", 200)))

    ; Wait for completion: "empty" = slot fully depleted, "change" = item transformed (e.g. ore→bar)
    if (waitMode = "change")
        done := WaitForSlotChange(ctx, presmeltSig, tol, smeltTimeoutMs)
    else
        done := WaitForSlotEmpty(ctx, indicatorSlot, tol, smeltTimeoutMs)

    if (!done) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "smelt")
        LogLine(LOG_FILE, "SmeltPhase: indicator slot never " (waitMode = "change" ? "changed" : "emptied") " within timeout")
        StopAndLog(ctx["runner"], "Smelting timed out - stopped")
        return GoToPhase(runner, "smelt")
    }

    LogLine(LOG_FILE, "SmeltPhase: smelting complete")
    ShowTipFor("Smelter: smelting done", 1500)
    return GoToPhase(runner, "walkBank")
}

; Phase 3: find first #0000FF pixel in bank region, click it, wait for deposit.png
WalkBankPhase(runner) {
    global ctx
    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "walkBank")

    ShowTip("Smelter: searching bank marker...")

    bm := CtxMarker(ctx, "BankWalkMarker")
    if (!WaitForPixelSearch(ctx, &bx, &by, bm["x1"], bm["y1"], bm["x2"], bm["y2"], bm["color"], bm["tolerance"], CtxTunable(ctx, "markerSearchTimeoutMs", 5000))) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "walkBank")
        LogLine(LOG_FILE, "WalkBank: marker not found - retrying")
        ShowTipFor("Smelter: bank marker not found - retrying", 2000)
        return GoToPhase(runner, "walkBank")
    }

    HumanClick(bx + bm["clickOffsetX"], by + bm["clickOffsetY"], 0, 0, ctx["runMode"])
    ResetPhaseTimer(ctx["runner"])
    ShowTip("Smelter: walking to bank...")

    depositImg := CtxImage(ctx, "DepositImg")
    if (!WaitForImageCenter(ctx, depositImg["x1"], depositImg["y1"], depositImg["x2"], depositImg["y2"],
                            depositImg["file"], depositImg["w"], depositImg["h"], &_cx, &_cy,
                            CtxTunable(ctx, "walkTimeoutMs", 30000),
                            depositImg.Has("options") ? depositImg["options"] : "")) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "walkBank")
        LogLine(LOG_FILE, "WalkBank: never arrived at bank - retrying")
        ShowTipFor("Smelter: never arrived at bank - retrying", 2000)
        return GoToPhase(runner, "walkBank")
    }

    LogLine(LOG_FILE, "WalkBank: arrived at bank")
    ShowTipFor("Smelter: arrived at bank", 1500)
    return GoToPhase(runner, "bank")
}

; Phase 4: deposit all, then withdraw per plan, loop back to furnace
BankPhase(runner) {
    global ctx
    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "bank")

    ShowTip("Smelter: banking...")

    depositImg := CtxImage(ctx, "DepositImg")

    if (!BankDepositAll(ctx, depositImg["file"], CtxTunable(ctx, "bankSettleMs", 300),
                        CtxTunable(ctx, "bankFailsafeMs", 300))) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "bank")
        LogLine(LOG_FILE, "BankPhase: deposit failed - bank may not be open")
        ShowTipFor("Smelter: deposit failed - retrying bank", 2000)
        return GoToPhase(runner, "bank")
    }

    plan := CtxWithdrawPlan(ctx, "Default")
    if (plan.Length > 0)
        BankWithdrawPlan(plan, CtxTunable(ctx, "withdrawInterSettleMs", 600),
                              CtxTunable(ctx, "withdrawFinalSettleMs", 300))

    LogLine(LOG_FILE, "BankPhase: deposited and withdrew, cycling back to furnace")
    ShowTipFor("Smelter: bank done - heading to furnace", 1500)
    return GoToPhase(runner, "walkFurnace")
}

; ============================================================
; CALIBRATION
; ============================================================

CalibrateIndicatorSlot() {
    global ctx
    prompt := InputBox("Which inventory slot (1-28) is the LAST slot with ore?`nScript waits for this slot to empty after smelting.", , , "28")
    if (prompt.Result = "Cancel")
        return
    slotIdx := Integer(prompt.Value)
    if (slotIdx < 1 || slotIdx > 28) {
        ShowTipFor("Invalid slot - must be 1-28", 1500)
        return
    }
    DbSet(CONFIG, "Settings", "indicatorSlot", slotIdx, "int")
    ctx["tunables"]["indicatorSlot"] := slotIdx
    ShowTipFor("Indicator slot set to " slotIdx, 1500)
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
    ctx["tunables"]["smeltTimeoutMs"]        := DbGet(CONFIG, "Tunables", "smeltTimeoutMs",        120000, "int")
    ctx["tunables"]["bankSettleMs"]          := DbGet(CONFIG, "Tunables", "bankSettleMs",          300,    "int")
    ctx["tunables"]["bankFailsafeMs"]        := DbGet(CONFIG, "Tunables", "bankFailsafeMs",        300,    "int")
    ctx["tunables"]["withdrawInterSettleMs"] := DbGet(CONFIG, "Tunables", "withdrawInterSettleMs", 600,    "int")
    ctx["tunables"]["withdrawFinalSettleMs"] := DbGet(CONFIG, "Tunables", "withdrawFinalSettleMs", 300,    "int")
    ctx["tunables"]["phaseTimeoutWalk"]      := DbGet(CONFIG, "Tunables", "phaseTimeoutWalk",      60000,  "int")
    ctx["tunables"]["phaseTimeoutSmelt"]     := DbGet(CONFIG, "Tunables", "phaseTimeoutSmelt",     180000, "int")
    ctx["tunables"]["phaseTimeoutBank"]      := DbGet(CONFIG, "Tunables", "phaseTimeoutBank",      30000,  "int")
    ctx["tunables"]["spaceKeySettleMs"]      := DbGet(CONFIG, "Tunables", "spaceKeySettleMs",      200,    "int")
    ctx["tunables"]["smeltWaitMode"]         := DbGet(CONFIG, "Tunables", "smeltWaitMode",         "empty", "str")

    ; Write all tunables back to ini so they appear in the file
    DbSet(CONFIG, "Tunables", "colorTolerance",        ctx["tunables"]["colorTolerance"],        "int")
    DbSet(CONFIG, "Tunables", "markerSearchTimeoutMs", ctx["tunables"]["markerSearchTimeoutMs"], "int")
    DbSet(CONFIG, "Tunables", "walkTimeoutMs",         ctx["tunables"]["walkTimeoutMs"],         "int")
    DbSet(CONFIG, "Tunables", "smeltTimeoutMs",        ctx["tunables"]["smeltTimeoutMs"],        "int")
    DbSet(CONFIG, "Tunables", "bankSettleMs",          ctx["tunables"]["bankSettleMs"],          "int")
    DbSet(CONFIG, "Tunables", "bankFailsafeMs",        ctx["tunables"]["bankFailsafeMs"],        "int")
    DbSet(CONFIG, "Tunables", "withdrawInterSettleMs", ctx["tunables"]["withdrawInterSettleMs"], "int")
    DbSet(CONFIG, "Tunables", "withdrawFinalSettleMs", ctx["tunables"]["withdrawFinalSettleMs"], "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutWalk",      ctx["tunables"]["phaseTimeoutWalk"],      "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutSmelt",     ctx["tunables"]["phaseTimeoutSmelt"],     "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutBank",      ctx["tunables"]["phaseTimeoutBank"],      "int")
    DbSet(CONFIG, "Tunables", "spaceKeySettleMs",      ctx["tunables"]["spaceKeySettleMs"],      "int")
    DbSet(CONFIG, "Tunables", "smeltWaitMode",         ctx["tunables"]["smeltWaitMode"],         "str")

    ; --- Settings ---
    ctx["runMode"]                   := DbGet(CONFIG, "Settings", "runMode",       true, "bool")
    ctx["tunables"]["indicatorSlot"] := DbGet(CONFIG, "Settings", "indicatorSlot", 28,   "int")

    ; --- Furnace walk marker (ini-driven, defaults match original working values) ---
    ctx["markers"]["FurnaceWalkMarker"] := DbGetMarker(CONFIG, "Marker:FurnaceWalkMarker")
    if (ctx["markers"]["FurnaceWalkMarker"]["color"] = -1) {
        DbSetMarker(CONFIG, "Marker:FurnaceWalkMarker", 0xFF00FF, 20, 140, 935, 315, 1050, 0, 0)
        ctx["markers"]["FurnaceWalkMarker"] := DbGetMarker(CONFIG, "Marker:FurnaceWalkMarker")
    }

    ; --- Bank walk marker ---
    ctx["markers"]["BankWalkMarker"] := DbGetMarker(CONFIG, "Marker:BankWalkMarker")
    if (ctx["markers"]["BankWalkMarker"]["color"] = -1) {
        DbSetMarker(CONFIG, "Marker:BankWalkMarker", 0x0000FF, 20, 1485, 375, 1615, 490, 0, 0)
        ctx["markers"]["BankWalkMarker"] := DbGetMarker(CONFIG, "Marker:BankWalkMarker")
    }

    ; --- Images (from Grid.ahk helpers; not user-edited) ---
    ctx["images"]["SmeltCookImg"] := GetSmeltCookIndicatorImage()
    ctx["images"]["DepositImg"]   := GetDepositButtonImage()

    ; --- Withdraw plan: persisted in ini, defaults to slot 1 x4 + slot 2 x1 ---
    plan := DbGetWithdrawPlan(CONFIG, "WithdrawPlan:Default")
    if (plan.Length = 0) {
        defaultPlan := [Map("slot", 1, "count", 4), Map("slot", 2, "count", 1)]
        DbSetWithdrawPlan(CONFIG, "WithdrawPlan:Default", defaultPlan)
        ctx["withdrawPlans"]["Default"] := defaultPlan
    } else {
        ctx["withdrawPlans"]["Default"] := plan
    }
}

ValidateSetup() {
    global ctx
    v := NewValidator()

    ; Markers are hardcoded - verify the regions are on-screen
    fm := ctx["markers"]["FurnaceWalkMarker"]
    bm := ctx["markers"]["BankWalkMarker"]
    RequireRegion(v, "Furnace walk marker region",  fm["x1"], fm["y1"], fm["x2"], fm["y2"])
    RequireRegion(v, "Bank walk marker region",     bm["x1"], bm["y1"], bm["x2"], bm["y2"])

    ; Images
    RequireFile(v, "Smelt-cook dialog image", ctx["images"]["SmeltCookImg"]["file"])
    RequireFile(v, "Deposit button image",    ctx["images"]["DepositImg"]["file"])

    ; Indicator slot
    slot := CtxTunable(ctx, "indicatorSlot", 0)
    if (slot < 1 || slot > 28)
        v["errors"].Push("Indicator slot is not configured (press F1)")

    ; Withdraw plan
    RequireNonEmpty(v, "Withdraw plan", ctx["withdrawPlans"]["Default"])

    return ShowValidationErrors(v)
}
