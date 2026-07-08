; ============================================================
; template-bot.ahk
;
; End-to-end v3 foundation example script - exercises every new
; primitive once. NOT one of the 7 real bots, but a minimal working
; skeleton demonstrating:
; - Context object usage (no global X,Y,Z boilerplate)
; - Db.ahk config shapes (Element, Marker, SlotSignature, etc)
; - Slots.ahk (arbitrary-slot change detection)
; - Marker.ahk (click-confirm-press-slot sequence)
; - Walk.ahk (marker-click-then-wait-for-arrival)
; - Bank.ahk with unified withdraw plans
; - Targeting.ahk diagnostic (one-shot NPC blob-center detection)
;
; Runnable in isolation for testing the foundation (hotkeys register,
; basic phase flow works). In-game behavior verification deferred until
; a real bot is built on this pattern.
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
#Include ..\lib\Targeting.ahk
#Include ..\lib\Bank.ahk
#Include ..\lib\Validate.ahk
#Include ..\lib\TaskRunner.ahk
#Include ..\lib\Log.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

global CONFIG := A_ScriptDir "\..\config\template-bot.ini"
global LOG_FILE := A_ScriptDir "\..\logs\template-bot-debug.log"
global ctx := NewBotContext(CONFIG)

EnsureDbVersion(CONFIG)
LoadConfig()

; ============================================================
; HOTKEYS
; ============================================================

F1:: CalibrateResourceMarker()
F2:: CalibrateInventorySignature()
F3:: CalibrateBankMarker()
F4:: DiagnosticAcquireTarget()
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
    AddPhase(ctx["runner"], "gather", GatherPhase, CtxTunable(ctx, "phaseTimeoutGather", 30000))
    AddPhase(ctx["runner"], "bank", BankPhase, CtxTunable(ctx, "phaseTimeoutBank", 30000))
    StartTaskRunner(ctx["runner"], "gather")
    LogLine(LOG_FILE, "===== Bot started =====")
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

GatherPhase(runner) {
    global ctx
    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "gather")

    sig := CtxSlotSignature(ctx, "InventoryCheck")
    if (IsSlotUnchanged(sig, CtxTunable(ctx, "colorTolerance", 20)))
        return GoToPhase(runner, "bank")

    marker := CtxMarker(ctx, "ResourceMarker")
    confirm := CtxImage(ctx, "ConfirmDialog")
    ok := DoMarkerActionAndWaitForSlotChange(
        ctx, marker, CtxTunable(ctx, "markerTimeoutMs", 8000),
        confirm, CtxTunable(ctx, "confirmTimeoutMs", 15000),
        CtxTunable(ctx, "actionKey", "Space"), CtxTunable(ctx, "keySettleMs", 100),
        sig, CtxTunable(ctx, "colorTolerance", 20), CtxTunable(ctx, "actionTimeoutMs", 180000))

    if (!ok) {
        StopAndLog(runner, "Resource action failed or timed out")
        return GoToPhase(runner, "gather")
    }
    return GoToPhase(runner, "bank")
}

BankPhase(runner) {
    global ctx
    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "bank")

    bankMarker := CtxMarker(ctx, "BankMarker")
    depositImg := CtxImage(ctx, "DepositButtonImg")
    arrival := Map("mode", "appear", "file", depositImg["file"], "w", depositImg["w"], "h", depositImg["h"],
                   "x1", depositImg["x1"], "y1", depositImg["y1"], "x2", depositImg["x2"], "y2", depositImg["y2"],
                   "options", depositImg.Has("options") ? depositImg["options"] : "")

    if (!WalkToMarker(ctx, bankMarker, CtxTunable(ctx, "bankMarkerTimeoutMs", 8000),
                      arrival, CtxTunable(ctx, "arrivalTimeoutMs", 15000))) {
        StopAndLog(runner, "Never arrived at bank")
        return GoToPhase(runner, "bank")
    }

    if (!BankDepositAll(ctx, depositImg["file"], 300, 300))
        return GoToPhase(runner, "bank")

    plan := CtxWithdrawPlan(ctx, "Default")
    if (plan.Length > 0)
        BankWithdrawPlan(plan, 600, 300)

    sig := CtxSlotSignature(ctx, "InventoryCheck")
    ctx["slotSignatures"]["InventoryCheck"] := RecaptureSlotSignature(sig)

    return GoToPhase(runner, "gather")
}

; ============================================================
; DIAGNOSTICS
; ============================================================

DiagnosticAcquireTarget() {
    global ctx
    region := CtxTargetRegion(ctx, "CombatArea")
    MouseGetPos(&mx, &my)
    if (AcquireTarget(ctx, region, mx, my, CtxTunable(ctx, "blobRadius", 60)))
        ShowTipFor("Target acquired and clicked", 1500)
    else
        ShowTipFor("No target blob found in region", 1500)
}

; ============================================================
; CALIBRATION HOTKEYS
; ============================================================

CalibrateResourceMarker() {
    global ctx
    cornerPrompt := InputBox("Mark resource marker. Enter '1' for corner 1, '2' for corner 2, or just press Cancel to skip")
    if (cornerPrompt.Result = "Cancel")
        return

    MouseGetPos(&mx, &my)
    if (cornerPrompt.Result = "1") {
        ctx["calibMarker1"] := {x: mx, y: my}
        ShowTipFor("Resource marker corner 1 set - now press again for corner 2", 2000)
    } else if (cornerPrompt.Result = "2" && ctx.Has("calibMarker1")) {
        corner1 := ctx["calibMarker1"]
        x1 := Min(corner1.x, mx)
        y1 := Min(corner1.y, my)
        x2 := Max(corner1.x, mx)
        y2 := Max(corner1.y, my)
        DbSetMarker(CONFIG, "Marker:ResourceMarker", 0xFF00FF, 20, x1, y1, x2, y2, 10, 10)
        ctx["markers"]["ResourceMarker"] := DbGetMarker(CONFIG, "Marker:ResourceMarker")
        ShowTipFor("Resource marker region saved", 2000)
    }
}

CalibrateInventorySignature() {
    global ctx
    slotPrompt := InputBox("Which inventory slot (1-28) to calibrate?", , , "28")
    if (slotPrompt.Result = "Cancel")
        return

    slotIndex := Integer(slotPrompt.Value)
    if (slotIndex < 1 || slotIndex > 28) {
        ShowTipFor("Invalid slot - must be 1-28", 1500)
        return
    }

    sig := CalibrateSlotSignature(slotIndex)
    DbSetSlotSignature(CONFIG, "SlotSignature:InventoryCheck", slotIndex, sig["points"])
    ctx["slotSignatures"]["InventoryCheck"] := sig
    ShowTipFor("Slot " slotIndex " calibrated", 1500)
}

CalibrateBankMarker() {
    global ctx
    cornerPrompt := InputBox("Mark bank marker. Enter '1' for corner 1, '2' for corner 2")
    if (cornerPrompt.Result = "Cancel")
        return

    MouseGetPos(&mx, &my)
    if (cornerPrompt.Result = "1") {
        ctx["calibBank1"] := {x: mx, y: my}
        ShowTipFor("Bank marker corner 1 set - press again for corner 2", 2000)
    } else if (cornerPrompt.Result = "2" && ctx.Has("calibBank1")) {
        corner1 := ctx["calibBank1"]
        x1 := Min(corner1.x, mx)
        y1 := Min(corner1.y, my)
        x2 := Max(corner1.x, mx)
        y2 := Max(corner1.y, my)
        DbSetMarker(CONFIG, "Marker:BankMarker", 0x0000FF, 20, x1, y1, x2, y2, 10, 10)
        ctx["markers"]["BankMarker"] := DbGetMarker(CONFIG, "Marker:BankMarker")
        ShowTipFor("Bank marker region saved", 2000)
    }
}

; ============================================================
; CONFIG LOAD / SETUP VALIDATION
; ============================================================

LoadConfig() {
    global ctx, CONFIG
    DbSet(CONFIG, "Meta", "schemaVersion", 1, "int")

    ; Load tunables
    ctx["tunables"]["colorTolerance"] := DbGet(CONFIG, "Tunables", "colorTolerance", 20, "int")
    ctx["tunables"]["markerTimeoutMs"] := DbGet(CONFIG, "Tunables", "markerTimeoutMs", 8000, "int")
    ctx["tunables"]["confirmTimeoutMs"] := DbGet(CONFIG, "Tunables", "confirmTimeoutMs", 15000, "int")
    ctx["tunables"]["actionKey"] := DbGet(CONFIG, "Tunables", "actionKey", "Space", "str")
    ctx["tunables"]["keySettleMs"] := DbGet(CONFIG, "Tunables", "keySettleMs", 100, "int")
    ctx["tunables"]["actionTimeoutMs"] := DbGet(CONFIG, "Tunables", "actionTimeoutMs", 180000, "int")
    ctx["tunables"]["phaseTimeoutGather"] := DbGet(CONFIG, "Tunables", "phaseTimeoutGather", 30000, "int")
    ctx["tunables"]["phaseTimeoutBank"] := DbGet(CONFIG, "Tunables", "phaseTimeoutBank", 30000, "int")
    ctx["tunables"]["bankMarkerTimeoutMs"] := DbGet(CONFIG, "Tunables", "bankMarkerTimeoutMs", 8000, "int")
    ctx["tunables"]["arrivalTimeoutMs"] := DbGet(CONFIG, "Tunables", "arrivalTimeoutMs", 15000, "int")
    ctx["tunables"]["blobRadius"] := DbGet(CONFIG, "Tunables", "blobRadius", 60, "int")

    ; Load settings
    ctx["runMode"] := DbGet(CONFIG, "Settings", "runMode", false, "bool")

    ; Load config shapes
    ctx["markers"]["ResourceMarker"] := DbGetMarker(CONFIG, "Marker:ResourceMarker")
    ctx["markers"]["BankMarker"] := DbGetMarker(CONFIG, "Marker:BankMarker")
    ctx["images"]["ConfirmDialog"] := DbGetImage(CONFIG, "Image:ConfirmDialog")
    ctx["images"]["DepositButtonImg"] := DbGetImage(CONFIG, "Image:DepositButtonImg")
    ctx["slotSignatures"]["InventoryCheck"] := DbGetSlotSignature(CONFIG, "SlotSignature:InventoryCheck")
    ctx["withdrawPlans"]["Default"] := DbGetWithdrawPlan(CONFIG, "WithdrawPlan:Default")
    ctx["targetRegions"]["CombatArea"] := DbGetTargetRegion(CONFIG, "TargetRegion:CombatArea")
}

ValidateSetup() {
    global ctx
    v := NewValidator()
    rm := ctx["markers"]["ResourceMarker"]
    bm := ctx["markers"]["BankMarker"]
    RequireRegion(v, "Resource marker", rm["x1"], rm["y1"], rm["x2"], rm["y2"])
    RequireRegion(v, "Bank marker", bm["x1"], bm["y1"], bm["x2"], bm["y2"])
    RequireSlotSignature(v, "Inventory signature", ctx["slotSignatures"]["InventoryCheck"])
    RequireFile(v, "Confirm dialog image", ctx["images"]["ConfirmDialog"]["file"])
    RequireFile(v, "Deposit button image", ctx["images"]["DepositButtonImg"]["file"])
    return ShowValidationErrors(v)
}
