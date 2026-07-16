; ============================================================
; smelter.ahk
; v4 entry point + all Smelter phases, one file (single
; bot/single loop, same shape as Motherlode/Firemaking). Shared
; framework classes stay in their own files.
;
; First version: assumes F5 is pressed with a full inventory of
; ore already in hand - withdrawing when NOT already full is a
; later addition.
;
; Isolation: reads/writes only v4's own config/ and logs/ - never
; the legacy repo-root config/ or logs/ folders.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

#Include ..\..\Core\Engine.ahk
#Include ..\..\Core\EngineContext.ahk
#Include ..\..\Core\FailSafe.ahk
#Include ..\..\Core\Phase.ahk
#Include ..\..\Core\SharedPhases.ahk
#Include ..\..\Timing\Waiter.ahk
#Include ..\..\Detection\ColorSearch.ahk
#Include ..\..\Detection\Telemetry.ahk
#Include ..\..\Detection\StaticAnchor.ahk
#Include ..\..\Interfaces\Inventory.ahk
#Include ..\..\Interfaces\Bank.ahk
#Include ..\..\Actions\Humanizer.ahk
#Include ..\..\Actions\Click.ahk
#Include ..\..\Actions\KeyAction.ahk
#Include ..\..\Config\Config.ahk
#Include ..\..\Diagnostics\Logger.ahk
#Include ..\..\Diagnostics\WindowFocus.ahk
#Include ..\..\Diagnostics\Overlay.ahk

; ============================================================
; GoToFurnacePhase - verifies the magenta furnace marker, clicks
; it, then waits for craft-marker-1.png (the "smelt X" dialog)
; to appear.
;
; Exit: once the dialog image is found, transitions to smelt.
; ============================================================
class GoToFurnacePhase extends Phase {
    __New(markerX, markerY, markerW, markerH, markerColor, markerTolerance, searchPaddingPx, reclickCooldownMs, markerWaitTimeoutMs, craftAnchor, craftWaitTimeoutMs, craftPollKey, runMode := false) {
        super.__New("goToFurnace")
        this._markerX := markerX
        this._markerY := markerY
        this._markerW := markerW
        this._markerH := markerH
        this._markerColor := markerColor
        this._markerTolerance := markerTolerance
        this._searchPaddingPx := searchPaddingPx
        this._reclickCooldownMs := reclickCooldownMs
        this._markerWaitTimeoutMs := markerWaitTimeoutMs
        this._craftAnchor := craftAnchor
        this._craftWaitTimeoutMs := craftWaitTimeoutMs
        this._craftPollKey := craftPollKey
        this._runMode := runMode
    }

    ResetForNewCycle() {
        ; Scratch timestamps are reset by DepositAndWithdrawPhase's
        ; per-cycle reset.
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "goToFurnace"

        rx1 := Max(0, this._markerX - this._searchPaddingPx)
        ry1 := Max(0, this._markerY - this._searchPaddingPx)
        rx2 := Min(A_ScreenWidth, this._markerX + this._searchPaddingPx)
        ry2 := Min(A_ScreenHeight, this._markerY + this._searchPaddingPx)

        found := ColorSearch.FindFilledBlock(rx1, ry1, rx2, ry2,
            this._markerColor, this._markerTolerance, this._markerW, this._markerH, &cx, &cy,
            false, this._markerX, this._markerY)

        if (!found) {
            waitStartedAt := ctx.Get("furnaceMarkerWaitStartedAt", 0)
            if (waitStartedAt == 0) {
                ctx.Set("furnaceMarkerWaitStartedAt", A_TickCount)
            } else if ((A_TickCount - waitStartedAt) > this._markerWaitTimeoutMs) {
                ctx.Log("GoToFurnacePhase: Timed out waiting for the furnace marker - stopping")
                ctx.engine.Stop("Timed out waiting for furnace marker")
                return "goToFurnace"
            }

            lastClick := ctx.Get("furnaceMarkerLastClickTime", 0)
            if (lastClick == 0 || (A_TickCount - lastClick) > this._reclickCooldownMs) {
                ctx.clicker.ClickSettled(ctx, this._markerX, this._markerY, this._runMode)
                ctx.Set("furnaceMarkerLastClickTime", A_TickCount)
                ctx.Log("GoToFurnacePhase: Clicked furnace marker at [" this._markerX ", " this._markerY "]")
                ctx.failsafe.ResetPhaseTimer(ctx)
            }
            return "goToFurnace"
        }

        if (!ctx.Get("furnaceMarkerClicked", false)) {
            ctx.Log("GoToFurnacePhase: Found furnace marker at [" cx ", " cy "]")
            ctx.clicker.ClickSettled(ctx, cx, cy, this._runMode)
            ctx.Set("furnaceMarkerClicked", true)
            ctx.failsafe.ResetPhaseTimer(ctx)
        }

        ctx.Log("GoToFurnacePhase: Waiting for smelt dialog...")
        if (!this._craftAnchor.WaitFor(ctx.waiter, ctx.timing, this._craftPollKey, this._craftWaitTimeoutMs, &dx, &dy)) {
            ctx.Log("GoToFurnacePhase: Timed out waiting for smelt dialog - stopping")
            ctx.engine.Stop("Timed out waiting for smelt dialog")
            return "goToFurnace"
        }

        ctx.Log("GoToFurnacePhase: Smelt dialog visible. Confirming.")
        return "smelt"
    }
}

; GoToBankPhase is the shared class from Core/SharedPhases.ahk - see
; Wiring below.

; ============================================================
; SmeltPhase - presses space once to confirm the smelt dialog,
; calibrating a SlotSignatureGate baseline on the ore-filled
; indicator slot at that instant, then waits until that slot's
; contents change (ore -> bar) - NOT until the slot empties,
; since a smelted bar still occupies the slot, so SlotGate/
; IsEmpty() never fires. Bot-specific rather than the shared
; PressAndWaitEmptyPhase for exactly this reason.
;
; Exit: once the slot's signature changes, transitions to goToBank.
; ============================================================
class SmeltPhase extends Phase {
    __New(keyAction, spaceSettleKey, signatureGate) {
        super.__New("smelt")
        this._keyAction := keyAction
        this._spaceSettleKey := spaceSettleKey
        this._signatureGate := signatureGate
    }

    ResetForNewCycle() {
        ; keyPressed is reset by DepositAndWithdrawPhase's per-cycle reset.
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "smelt"

        if (!ctx.Get("keyPressed", false)) {
            this._keyAction.Press("space")
            ctx.waiter.After(ctx.timing, this._spaceSettleKey)
            ; Calibrate while ore is still visible in the slot, right after
            ; confirming the dialog - the baseline this bot's "done" check
            ; compares against for the rest of this smelt.
            this._signatureGate.Calibrate()
            ctx.Set("keyPressed", true)
            ctx.Log("SmeltPhase: Pressed space to confirm smelt dialog")
            ctx.failsafe.ResetPhaseTimer(ctx)
            return "smelt"
        }

        if (this._signatureGate.IsSet()) {
            ctx.Log("SmeltPhase: Indicator slot changed (ore -> bar). Moving to bank.")
            return "goToBank"
        }

        return "smelt"
    }
}

; ============================================================
; DepositAndWithdrawPhase - re-finds deposit-default.png and
; clicks its own found center (deposit-all), then withdraws a
; multi-slot plan (each slot clicked its own configured number
; of times), then settles and fully resets per-cycle state
; before handing off back to goToFurnace.
; ============================================================
class DepositAndWithdrawPhase extends Phase {
    ; withdrawPlan: array of {slotIndex, clicks} in withdraw order.
    __New(bankOpenAnchor, bankOpenPollKey, bankOpenWaitTimeoutMs, bank, withdrawPlan, clickIntervalMs, settleDelayKey, nextCyclePhases, runMode := false) {
        super.__New("depositAndWithdraw")
        this._bankOpenAnchor := bankOpenAnchor
        this._bankOpenPollKey := bankOpenPollKey
        this._bankOpenWaitTimeoutMs := bankOpenWaitTimeoutMs
        this._bank := bank
        this._withdrawPlan := withdrawPlan
        this._clickIntervalMs := clickIntervalMs
        this._settleDelayKey := settleDelayKey
        this._nextCyclePhases := nextCyclePhases
        this._runMode := runMode
    }

    ResetForNewCycle() {
        ; depositClicked/withdrawPlanIndex/withdrawClicksDone are reset by
        ; this phase's own completion below.
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "depositAndWithdraw"

        if (!ctx.Get("depositClicked", false)) {
            if (!this._bankOpenAnchor.WaitFor(ctx.waiter, ctx.timing, this._bankOpenPollKey, this._bankOpenWaitTimeoutMs, &dx, &dy)) {
                ctx.Log("DepositAndWithdrawPhase: Timed out waiting for deposit box - stopping")
                ctx.engine.Stop("Timed out waiting for deposit box")
                return "depositAndWithdraw"
            }

            ctx.clicker.ClickSettled(ctx, dx, dy, this._runMode)
            ctx.Set("depositClicked", true)
            ctx.Log("DepositAndWithdrawPhase: Deposited ingots at [" dx ", " dy "]")
            ctx.failsafe.ResetPhaseTimer(ctx)
            return "depositAndWithdraw"
        }

        planIndex := ctx.Get("withdrawPlanIndex", 1)
        if (planIndex <= this._withdrawPlan.Length) {
            entry := this._withdrawPlan[planIndex]
            clicksDone := ctx.Get("withdrawClicksDone", 0)

            if (clicksDone >= entry["clicks"]) {
                ctx.Set("withdrawPlanIndex", planIndex + 1)
                ctx.Set("withdrawClicksDone", 0)
                return "depositAndWithdraw"
            }

            lastClick := ctx.Get("withdrawLastClickTime", 0)
            if (lastClick != 0 && (A_TickCount - lastClick) < this._clickIntervalMs)
                return "depositAndWithdraw"

            this._bank.WithdrawSlot(entry["slotIndex"], &x, &y)
            ctx.clicker.ClickSettled(ctx, x, y, this._runMode)
            ctx.Set("withdrawClicksDone", clicksDone + 1)
            ctx.Set("withdrawLastClickTime", A_TickCount)
            ctx.Log("DepositAndWithdrawPhase: Clicked bank slot " entry["slotIndex"] " at [" x ", " y "] (" clicksDone + 1 "/" entry["clicks"] ")")
            ctx.failsafe.ResetPhaseTimer(ctx)
            return "depositAndWithdraw"
        }

        ; One-time settle delay before handing off - the furnace marker may
        ; not be rendered/stable in the client immediately after
        ; withdrawing (character/camera still catching up), same bug class
        ; fixed repeatedly in Motherlode/Firemaking. Tune this live.
        ctx.waiter.After(ctx.timing, this._settleDelayKey)

        ctx.Log("DepositAndWithdrawPhase: Withdraw plan complete. Handing off to furnace phase.")

        ctx.Set("furnaceMarkerWaitStartedAt", 0)
        ctx.Set("furnaceMarkerLastClickTime", 0)
        ctx.Set("furnaceMarkerClicked", false)
        ctx.Set("keyPressed", false)
        ctx.Set("bankMarkerWaitStartedAt", 0)
        ctx.Set("bankMarkerLastClickTime", 0)
        ctx.Set("bankMarkerClicked", false)
        ctx.Set("depositClicked", false)
        ctx.Set("withdrawPlanIndex", 1)
        ctx.Set("withdrawClicksDone", 0)
        ctx.Set("withdrawLastClickTime", 0)
        for phase in this._nextCyclePhases
            phase.ResetForNewCycle()

        return "goToFurnace"
    }
}

; ============================================================
; Wiring
; ============================================================

schema := Map(
    "runnerTickMs", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutFurnace", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutBank", Map("section", "Tunables", "type", "int"),
    "colorTolerance", Map("section", "Tunables", "type", "int"),
    "furnaceMarkerX", Map("section", "Tunables", "type", "int"),
    "furnaceMarkerY", Map("section", "Tunables", "type", "int"),
    "furnaceMarkerW", Map("section", "Tunables", "type", "int"),
    "furnaceMarkerH", Map("section", "Tunables", "type", "int"),
    "furnaceMarkerColor", Map("section", "Tunables", "type", "color"),
    "furnaceMarkerTolerance", Map("section", "Tunables", "type", "int"),
    "furnaceMarkerSearchPaddingPx", Map("section", "Tunables", "type", "int"),
    "furnaceMarkerReclickCooldownMs", Map("section", "Tunables", "type", "int"),
    "furnaceMarkerWaitTimeoutMs", Map("section", "Tunables", "type", "int"),
    "craftMarkerAnchorX", Map("section", "Tunables", "type", "int"),
    "craftMarkerAnchorY", Map("section", "Tunables", "type", "int"),
    "craftMarkerImageW", Map("section", "Tunables", "type", "int"),
    "craftMarkerImageH", Map("section", "Tunables", "type", "int"),
    "craftMarkerSearchPaddingPx", Map("section", "Tunables", "type", "int"),
    "craftMarkerWaitTimeoutMs", Map("section", "Tunables", "type", "int"),
    "smeltIndicatorSlot", Map("section", "Tunables", "type", "int"),
    "bankMarkerX", Map("section", "Tunables", "type", "int"),
    "bankMarkerY", Map("section", "Tunables", "type", "int"),
    "bankMarkerW", Map("section", "Tunables", "type", "int"),
    "bankMarkerH", Map("section", "Tunables", "type", "int"),
    "bankMarkerColor", Map("section", "Tunables", "type", "color"),
    "bankMarkerTolerance", Map("section", "Tunables", "type", "int"),
    "bankMarkerSearchPaddingPx", Map("section", "Tunables", "type", "int"),
    "bankMarkerReclickCooldownMs", Map("section", "Tunables", "type", "int"),
    "bankMarkerWaitTimeoutMs", Map("section", "Tunables", "type", "int"),
    "bankOpenAnchorX", Map("section", "Tunables", "type", "int"),
    "bankOpenAnchorY", Map("section", "Tunables", "type", "int"),
    "bankOpenImageW", Map("section", "Tunables", "type", "int"),
    "bankOpenImageH", Map("section", "Tunables", "type", "int"),
    "bankOpenSearchPaddingPx", Map("section", "Tunables", "type", "int"),
    "bankOpenWaitTimeoutMs", Map("section", "Tunables", "type", "int"),
    "bankSlotFirstX", Map("section", "Tunables", "type", "int"),
    "bankSlotFirstY", Map("section", "Tunables", "type", "int"),
    "bankSlotPitchX", Map("section", "Tunables", "type", "int"),
    "bankSlotW", Map("section", "Tunables", "type", "int"),
    "bankSlotH", Map("section", "Tunables", "type", "int"),
    "withdrawSlotCount", Map("section", "Tunables", "type", "int"),
    "withdrawSlot1Index", Map("section", "Tunables", "type", "int"),
    "withdrawSlot1Clicks", Map("section", "Tunables", "type", "int"),
    "withdrawSlot2Index", Map("section", "Tunables", "type", "int"),
    "withdrawSlot2Clicks", Map("section", "Tunables", "type", "int"),
    "withdrawClickIntervalMs", Map("section", "Tunables", "type", "int"),
    "runMode", Map("section", "Settings", "type", "int")
)
timingSchema := Map(
    "clickSettle", Map("section", "Tunables", "baseMsKey", "clickSettleMs", "jitterPercentKey", "clickSettleJitterPercent"),
    "ctrlHoldSettle", Map("section", "Tunables", "baseMsKey", "ctrlHoldSettleMs", "jitterPercentKey", "clickSettleJitterPercent"),
    "craftMarkerPoll", Map("section", "Tunables", "baseMsKey", "craftMarkerPollMs"),
    "spacePressSettle", Map("section", "Tunables", "baseMsKey", "spacePressSettleMs"),
    "bankOpenPoll", Map("section", "Tunables", "baseMsKey", "bankOpenPollMs"),
    "postWithdrawSettle", Map("section", "Tunables", "baseMsKey", "postWithdrawSettleDelayMs")
)

iniPath := A_ScriptDir "\..\..\Config\smelter-gold.ini"
botConfig := Config(iniPath, schema, timingSchema)
botConfig.Load()

botLogger := Logger(A_ScriptDir "\..\..\logs\auto-smelter-v4-debug.log")
botHumanizer := Humanizer(false)
botClicker := Clicker(botHumanizer)
botFailsafe := FailSafe(botLogger)
botWaiter := Waiter((baseMs, jitterPercent) => botHumanizer.Jitter(baseMs, jitterPercent))
botWindowFocus := WindowFocus()
botOverlay := Overlay(8, 10, 10)
botKeyAction := KeyAction()

ctx := EngineContext(botConfig, botLogger, botClicker, botFailsafe, botWaiter, botWindowFocus, botOverlay)

; Inventory layout is a fixed property of this client window (not a
; game-state tunable), so it's a hardcoded constant - same values as
; Motherlode/Firemaking's calibration for this window.
inventoryLayout := Map("firstX", 2099, "firstY", 801, "cols", 4, "rows", 7, "slotW", 72, "slotH", 64, "gapX", 12, "gapY", 8)
ctx.inventory := Inventory(inventoryLayout)

; craft-marker-1.png - shown once the "smelt X" dialog opens (same image
; Firemaking uses for its own crafting dialog).
craftImagePath := A_ScriptDir "\..\..\Images\craft-marker-1.png"
craftImageRegion := Map(
    "x1", botConfig.Get("craftMarkerAnchorX") - botConfig.Get("craftMarkerSearchPaddingPx"),
    "y1", botConfig.Get("craftMarkerAnchorY") - botConfig.Get("craftMarkerSearchPaddingPx"),
    "x2", botConfig.Get("craftMarkerAnchorX") + botConfig.Get("craftMarkerImageW") + botConfig.Get("craftMarkerSearchPaddingPx"),
    "y2", botConfig.Get("craftMarkerAnchorY") + botConfig.Get("craftMarkerImageH") + botConfig.Get("craftMarkerSearchPaddingPx")
)
craftAnchor := ImageAnchor(craftImageRegion, craftImagePath, botConfig.Get("craftMarkerImageW"), botConfig.Get("craftMarkerImageH"))

; deposit-default.png - clicked directly as deposit-all (unlike Firemaking,
; where this same image is only a detection signal).
bankOpenImagePath := A_ScriptDir "\..\..\Images\deposit-default.png"
bankOpenImageRegion := Map(
    "x1", botConfig.Get("bankOpenAnchorX") - botConfig.Get("bankOpenSearchPaddingPx"),
    "y1", botConfig.Get("bankOpenAnchorY") - botConfig.Get("bankOpenSearchPaddingPx"),
    "x2", botConfig.Get("bankOpenAnchorX") + botConfig.Get("bankOpenImageW") + botConfig.Get("bankOpenSearchPaddingPx"),
    "y2", botConfig.Get("bankOpenAnchorY") + botConfig.Get("bankOpenImageH") + botConfig.Get("bankOpenSearchPaddingPx")
)
bankOpenAnchor := ImageAnchor(bankOpenImageRegion, bankOpenImagePath, botConfig.Get("bankOpenImageW"), botConfig.Get("bankOpenImageH"))

bankSlotLayout := Map(
    "firstX", botConfig.Get("bankSlotFirstX"), "firstY", botConfig.Get("bankSlotFirstY"),
    "pitchX", botConfig.Get("bankSlotPitchX"), "slotW", botConfig.Get("bankSlotW"), "slotH", botConfig.Get("bankSlotH")
)
; chestAnchor/depositAllAnchor are unused by this bot's own Bank methods
; (GoToBankPhase/DepositAndWithdrawPhase click markers/images directly via
; ColorSearch/StaticAnchor, not through Bank.OpenChest/DepositAll) - Bank is
; constructed here only for its WithdrawSlot coordinate math.
botBank := Bank(bankOpenAnchor, bankOpenAnchor, botClicker, bankSlotLayout)

; Withdraw plan: ordered list of {slotIndex, clicks}, built from .ini so the
; slot count/indices/click counts are all tunable, not hardcoded.
withdrawPlan := []
loop botConfig.Get("withdrawSlotCount") {
    n := A_Index
    withdrawPlan.Push(Map("slotIndex", botConfig.Get("withdrawSlot" n "Index"), "clicks", botConfig.Get("withdrawSlot" n "Clicks")))
}

botGoToFurnacePhase := GoToFurnacePhase(
    botConfig.Get("furnaceMarkerX"), botConfig.Get("furnaceMarkerY"),
    botConfig.Get("furnaceMarkerW"), botConfig.Get("furnaceMarkerH"),
    botConfig.Get("furnaceMarkerColor"), botConfig.Get("furnaceMarkerTolerance"),
    botConfig.Get("furnaceMarkerSearchPaddingPx"), botConfig.Get("furnaceMarkerReclickCooldownMs"),
    botConfig.Get("furnaceMarkerWaitTimeoutMs"), craftAnchor,
    botConfig.Get("craftMarkerWaitTimeoutMs"), "craftMarkerPoll", botConfig.Get("runMode")
)

; Detects "this slot's ore became a bar" - unlike the full/empty gate
; above, a smelted bar still occupies the slot, so IsEmpty() never fires.
smeltSignatureGate := SlotSignatureGate(botConfig.Get("smeltIndicatorSlot"), botConfig.Get("colorTolerance"), ctx.inventory)
botSmeltPhase := SmeltPhase(botKeyAction, "spacePressSettle", smeltSignatureGate)

botGoToBankPhase := GoToBankPhase(
    botConfig.Get("bankMarkerX"), botConfig.Get("bankMarkerY"),
    botConfig.Get("bankMarkerW"), botConfig.Get("bankMarkerH"),
    botConfig.Get("bankMarkerColor"), botConfig.Get("bankMarkerTolerance"),
    botConfig.Get("bankMarkerSearchPaddingPx"), botConfig.Get("bankMarkerReclickCooldownMs"),
    botConfig.Get("bankMarkerWaitTimeoutMs"), bankOpenAnchor,
    botConfig.Get("bankOpenWaitTimeoutMs"), "bankOpenPoll", "depositAndWithdraw", botConfig.Get("runMode")
)

nextCyclePhases := [botGoToFurnacePhase, botSmeltPhase, botGoToBankPhase]

botDepositAndWithdrawPhase := DepositAndWithdrawPhase(
    bankOpenAnchor, "bankOpenPoll", botConfig.Get("bankOpenWaitTimeoutMs"),
    botBank, withdrawPlan, botConfig.Get("withdrawClickIntervalMs"),
    "postWithdrawSettle", nextCyclePhases, botConfig.Get("runMode")
)
nextCyclePhases.Push(botDepositAndWithdrawPhase)

botEngine := Engine(ctx, botConfig.Get("runnerTickMs"))
ctx.engine := botEngine
botEngine.AddPhase(botGoToFurnacePhase, botConfig.Get("phaseTimeoutFurnace"))
botEngine.AddPhase(botSmeltPhase, botConfig.Get("phaseTimeoutFurnace"))
botEngine.AddPhase(botGoToBankPhase, botConfig.Get("phaseTimeoutBank"))
botEngine.AddPhase(botDepositAndWithdrawPhase, botConfig.Get("phaseTimeoutBank"))

F5:: botEngine.Start("goToFurnace")
F6:: {
    botEngine.Stop("Stopped (F6)")
    botOverlay.Clear()
}
