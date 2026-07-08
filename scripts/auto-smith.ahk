; ============================================================
; auto-smith.ahk - v3
;
; Cycle:
;   1. Ensure the calibrated indicator slot is not empty (bars present)
;   2. Click anvil marker, wait for craft dialog, press Space
;   3. Wait for the indicator slot to return to its calibrated empty state
;   4. Walk to bank marker, wait for deposit image, deposit all
;   5. Execute withdraw plan, loop
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

global CONFIG   := A_ScriptDir "\..\config\auto-smith.ini"
global LOG_FILE := A_ScriptDir "\..\logs\auto-smith-debug.log"
global ctx      := NewBotContext(CONFIG)

EnsureDbVersion(CONFIG)
LoadConfig()

; ============================================================
; HOTKEYS
; ============================================================

; Calibrate while inventory is empty.
; Pick the slot that is expected to be consumed last during smithing.
F1:: CalibrateIndicatorEmptySignature()
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
    AddPhase(ctx["runner"], "smith", SmithPhase, CtxTunable(ctx, "phaseTimeoutSmith", 180000))
    AddPhase(ctx["runner"], "bank",  BankPhase,  CtxTunable(ctx, "phaseTimeoutBank", 30000))
    StartTaskRunner(ctx["runner"], "smith")

    LogLine(LOG_FILE, "===== Smith bot started =====")
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

SmithPhase(runner) {
    global ctx
    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "smith")

    tol := CtxTunable(ctx, "colorTolerance", 20)
    emptySig := CtxSlotSignature(ctx, "IndicatorEmpty")

    ; Guard: after banking, inventory paint can lag briefly. Wait for occupied.
    if (!WaitForSlotChange(ctx, emptySig, tol, CtxTunable(ctx, "barsSettleTimeoutMs", 3000), CtxTunable(ctx, "barsConfirmTicks", 2))) {
        LogLine(LOG_FILE, "SmithPhase: indicator slot still empty - likely out of bars, re-banking")
        ShowTipFor("Smith: no bars detected - re-banking", 1500)
        return GoToPhase(runner, "bank")
    }

    anvilMarker := CtxMarker(ctx, "AnvilWalkMarker")
    craftImg := CtxImage(ctx, "CraftImg")

    ok := DoMarkerAction(
        ctx,
        anvilMarker,
        CtxTunable(ctx, "markerSearchTimeoutMs", 8000),
        craftImg,
        CtxTunable(ctx, "craftDialogTimeoutMs", 15000),
        CtxTunable(ctx, "actionKey", "Space"),
        CtxTunable(ctx, "actionKeySettleMs", 200)
    )

    if (!ok) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "smith")
        LogLine(LOG_FILE, "SmithPhase: failed to click anvil or confirm craft dialog - retrying")
        ShowTipFor("Smith: anvil/craft confirm failed - retrying", 2000)
        return GoToPhase(runner, "smith")
    }

    ResetPhaseTimer(ctx["runner"])
    ShowTip("Smith: smithing...")

    done := WaitForSlotUnchanged(ctx, emptySig, tol, CtxTunable(ctx, "smithTimeoutMs", 180000), CtxTunable(ctx, "slotConfirmTicks", 3))
    if (!done) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "smith")
        LogLine(LOG_FILE, "SmithPhase: indicator slot never returned to empty baseline")
        StopAndLog(ctx["runner"], "Smithing timed out - stopped")
        return GoToPhase(runner, "smith")
    }

    ResetPhaseTimer(ctx["runner"])
    LogLine(LOG_FILE, "SmithPhase: smithing complete")
    ShowTipFor("Smith: batch complete", 1500)
    return GoToPhase(runner, "bank")
}

BankPhase(runner) {
    global ctx
    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "bank")

    bankMarker := CtxMarker(ctx, "BankWalkMarker")
    depositImg := CtxImage(ctx, "DepositImg")

    arrival := Map(
        "mode", "appear",
        "file", depositImg["file"], "w", depositImg["w"], "h", depositImg["h"],
        "x1", depositImg["x1"], "y1", depositImg["y1"], "x2", depositImg["x2"], "y2", depositImg["y2"],
        "options", depositImg.Has("options") ? depositImg["options"] : ""
    )

    if (!WalkToMarker(ctx, bankMarker,
                      CtxTunable(ctx, "bankMarkerTimeoutMs", 8000),
                      arrival,
                      CtxTunable(ctx, "walkTimeoutMs", 30000))) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "bank")
        LogLine(LOG_FILE, "BankPhase: failed to arrive at bank - retrying")
        ShowTipFor("Smith: bank walk failed - retrying", 2000)
        return GoToPhase(runner, "bank")
    }

    if (!BankDepositAll(ctx,
                        depositImg["file"],
                        CtxTunable(ctx, "bankSettleMs", 300),
                        CtxTunable(ctx, "bankFailsafeMs", 300),
                        depositImg["w"],
                        depositImg["h"],
                        CtxTunable(ctx, "bankOpenTimeoutMs", 15000),
                        20,
                        depositImg.Has("options") ? depositImg["options"] : "*20")) {
        if (!CtxIsRunning(ctx))
            return GoToPhase(runner, "bank")
        LogLine(LOG_FILE, "BankPhase: deposit failed - bank may not be open")
        ShowTipFor("Smith: deposit failed - retrying", 2000)
        return GoToPhase(runner, "bank")
    }

    plan := CtxWithdrawPlan(ctx, "Default")
    if (plan.Length > 0) {
        BankWithdrawPlan(plan,
            CtxTunable(ctx, "withdrawInterSettleMs", 300),
            CtxTunable(ctx, "withdrawFinalSettleMs", 300))
    }

    LogLine(LOG_FILE, "BankPhase: deposited and withdrew supplies")
    ShowTipFor("Smith: bank done", 1200)
    return GoToPhase(runner, "smith")
}

; ============================================================
; CALIBRATION
; ============================================================

CalibrateIndicatorEmptySignature() {
    global ctx, CONFIG

    prompt := InputBox("Inventory must be EMPTY. Which slot (1-28) should be used as the smithing completion indicator?", , , "28")
    if (prompt.Result = "Cancel")
        return

    slotIdx := Integer(prompt.Value)
    if (slotIdx < 1 || slotIdx > 28) {
        ShowTipFor("Invalid slot - must be 1-28", 1500)
        return
    }

    sig := CalibrateSlotSignature(slotIdx)
    DbSetSlotSignature(CONFIG, "SlotSignature:IndicatorEmpty", slotIdx, sig["points"])
    ctx["slotSignatures"]["IndicatorEmpty"] := sig

    ShowTipFor("Saved empty baseline for slot " slotIdx, 1800)
}

; ============================================================
; CONFIG
; ============================================================

LoadConfig() {
    global ctx, CONFIG

    ; Tunables
    ctx["tunables"]["colorTolerance"]        := DbGet(CONFIG, "Tunables", "colorTolerance",        20,     "int")
    ctx["tunables"]["markerSearchTimeoutMs"] := DbGet(CONFIG, "Tunables", "markerSearchTimeoutMs", 8000,   "int")
    ctx["tunables"]["craftDialogTimeoutMs"]  := DbGet(CONFIG, "Tunables", "craftDialogTimeoutMs",  15000,  "int")
    ctx["tunables"]["actionKey"]             := DbGet(CONFIG, "Tunables", "actionKey",             "Space","str")
    ctx["tunables"]["actionKeySettleMs"]     := DbGet(CONFIG, "Tunables", "actionKeySettleMs",     200,    "int")
    ctx["tunables"]["barsSettleTimeoutMs"]   := DbGet(CONFIG, "Tunables", "barsSettleTimeoutMs",   3000,   "int")
    ctx["tunables"]["barsConfirmTicks"]      := DbGet(CONFIG, "Tunables", "barsConfirmTicks",      2,      "int")
    ctx["tunables"]["slotConfirmTicks"]      := DbGet(CONFIG, "Tunables", "slotConfirmTicks",      3,      "int")
    ctx["tunables"]["smithTimeoutMs"]        := DbGet(CONFIG, "Tunables", "smithTimeoutMs",        180000, "int")
    ctx["tunables"]["bankMarkerTimeoutMs"]   := DbGet(CONFIG, "Tunables", "bankMarkerTimeoutMs",   8000,   "int")
    ctx["tunables"]["walkTimeoutMs"]         := DbGet(CONFIG, "Tunables", "walkTimeoutMs",         30000,  "int")
    ctx["tunables"]["bankOpenTimeoutMs"]     := DbGet(CONFIG, "Tunables", "bankOpenTimeoutMs",     15000,  "int")
    ctx["tunables"]["bankSettleMs"]          := DbGet(CONFIG, "Tunables", "bankSettleMs",          300,    "int")
    ctx["tunables"]["bankFailsafeMs"]        := DbGet(CONFIG, "Tunables", "bankFailsafeMs",        300,    "int")
    ctx["tunables"]["withdrawInterSettleMs"] := DbGet(CONFIG, "Tunables", "withdrawInterSettleMs", 300,    "int")
    ctx["tunables"]["withdrawFinalSettleMs"] := DbGet(CONFIG, "Tunables", "withdrawFinalSettleMs", 300,    "int")
    ctx["tunables"]["phaseTimeoutSmith"]     := DbGet(CONFIG, "Tunables", "phaseTimeoutSmith",     180000, "int")
    ctx["tunables"]["phaseTimeoutBank"]      := DbGet(CONFIG, "Tunables", "phaseTimeoutBank",      30000,  "int")

    DbSet(CONFIG, "Tunables", "colorTolerance",        ctx["tunables"]["colorTolerance"],        "int")
    DbSet(CONFIG, "Tunables", "markerSearchTimeoutMs", ctx["tunables"]["markerSearchTimeoutMs"], "int")
    DbSet(CONFIG, "Tunables", "craftDialogTimeoutMs",  ctx["tunables"]["craftDialogTimeoutMs"],  "int")
    DbSet(CONFIG, "Tunables", "actionKey",             ctx["tunables"]["actionKey"],             "str")
    DbSet(CONFIG, "Tunables", "actionKeySettleMs",     ctx["tunables"]["actionKeySettleMs"],     "int")
    DbSet(CONFIG, "Tunables", "barsSettleTimeoutMs",   ctx["tunables"]["barsSettleTimeoutMs"],   "int")
    DbSet(CONFIG, "Tunables", "barsConfirmTicks",      ctx["tunables"]["barsConfirmTicks"],      "int")
    DbSet(CONFIG, "Tunables", "slotConfirmTicks",      ctx["tunables"]["slotConfirmTicks"],      "int")
    DbSet(CONFIG, "Tunables", "smithTimeoutMs",        ctx["tunables"]["smithTimeoutMs"],        "int")
    DbSet(CONFIG, "Tunables", "bankMarkerTimeoutMs",   ctx["tunables"]["bankMarkerTimeoutMs"],   "int")
    DbSet(CONFIG, "Tunables", "walkTimeoutMs",         ctx["tunables"]["walkTimeoutMs"],         "int")
    DbSet(CONFIG, "Tunables", "bankOpenTimeoutMs",     ctx["tunables"]["bankOpenTimeoutMs"],     "int")
    DbSet(CONFIG, "Tunables", "bankSettleMs",          ctx["tunables"]["bankSettleMs"],          "int")
    DbSet(CONFIG, "Tunables", "bankFailsafeMs",        ctx["tunables"]["bankFailsafeMs"],        "int")
    DbSet(CONFIG, "Tunables", "withdrawInterSettleMs", ctx["tunables"]["withdrawInterSettleMs"], "int")
    DbSet(CONFIG, "Tunables", "withdrawFinalSettleMs", ctx["tunables"]["withdrawFinalSettleMs"], "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutSmith",     ctx["tunables"]["phaseTimeoutSmith"],     "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutBank",      ctx["tunables"]["phaseTimeoutBank"],      "int")

    ; Settings
    ctx["runMode"] := DbGet(CONFIG, "Settings", "runMode", false, "bool")
    DbSet(CONFIG, "Settings", "runMode", ctx["runMode"], "bool")

    ; Markers
    ctx["markers"]["AnvilWalkMarker"] := DbGetMarker(CONFIG, "Marker:AnvilWalkMarker")
    if (ctx["markers"]["AnvilWalkMarker"]["color"] = -1) {
        DbSetMarker(CONFIG, "Marker:AnvilWalkMarker", 0xFF00FF, 20, 1649, 515, 1749, 590, 15, 15)
        ctx["markers"]["AnvilWalkMarker"] := DbGetMarker(CONFIG, "Marker:AnvilWalkMarker")
    }

    ctx["markers"]["BankWalkMarker"] := DbGetMarker(CONFIG, "Marker:BankWalkMarker")
    if (ctx["markers"]["BankWalkMarker"]["color"] = -1) {
        DbSetMarker(CONFIG, "Marker:BankWalkMarker", 0x0000FF, 20, 549, 706, 699, 806, 15, 25)
        ctx["markers"]["BankWalkMarker"] := DbGetMarker(CONFIG, "Marker:BankWalkMarker")
    }

    ; Images
    ctx["images"]["CraftImg"] := DbGetImage(CONFIG, "Image:CraftImg")
    if (ctx["images"]["CraftImg"]["file"] = "") {
        craft := GetCraftIndicatorImage()
        DbSetImage(CONFIG, "Image:CraftImg", craft["file"], craft["w"], craft["h"],
            craft.Has("options") ? craft["options"] : "",
            craft["x1"], craft["y1"], craft["x2"], craft["y2"])
        ctx["images"]["CraftImg"] := DbGetImage(CONFIG, "Image:CraftImg")
    }

    ctx["images"]["DepositImg"] := DbGetImage(CONFIG, "Image:DepositImg")
    if (ctx["images"]["DepositImg"]["file"] = "") {
        dep := GetDepositButtonImage()
        DbSetImage(CONFIG, "Image:DepositImg", dep["file"], dep["w"], dep["h"],
            dep.Has("options") ? dep["options"] : "",
            dep["x1"], dep["y1"], dep["x2"], dep["y2"])
        ctx["images"]["DepositImg"] := DbGetImage(CONFIG, "Image:DepositImg")
    }

    ; Slot signature baseline (calibrated by F1)
    ctx["slotSignatures"]["IndicatorEmpty"] := DbGetSlotSignature(CONFIG, "SlotSignature:IndicatorEmpty")

    ; Withdraw plan
    plan := DbGetWithdrawPlan(CONFIG, "WithdrawPlan:Default")
    if (plan.Length = 0) {
        plan := [
            Map("slot", 1, "count", 1),
            Map("slot", 2, "count", 1)
        ]
        DbSetWithdrawPlan(CONFIG, "WithdrawPlan:Default", plan)
    }
    ctx["withdrawPlans"]["Default"] := plan
}

; ============================================================
; VALIDATION
; ============================================================

ValidateSetup() {
    global ctx
    v := NewValidator()

    am := CtxMarker(ctx, "AnvilWalkMarker")
    bm := CtxMarker(ctx, "BankWalkMarker")
    RequireRegion(v, "Anvil walk marker region", am["x1"], am["y1"], am["x2"], am["y2"])
    RequireColor(v, "Anvil walk marker color", am["color"])
    RequireRegion(v, "Bank walk marker region", bm["x1"], bm["y1"], bm["x2"], bm["y2"])
    RequireColor(v, "Bank walk marker color", bm["color"])

    RequireSlotSignature(v, "Indicator empty signature (F1)", CtxSlotSignature(ctx, "IndicatorEmpty"))

    craft := CtxImage(ctx, "CraftImg")
    dep := CtxImage(ctx, "DepositImg")
    RequireFile(v, "Craft dialog image", craft["file"])
    RequireFile(v, "Deposit image", dep["file"])

    RequireNonEmpty(v, "Withdraw plan", CtxWithdrawPlan(ctx, "Default"))

    return ShowValidationErrors(v)
}
