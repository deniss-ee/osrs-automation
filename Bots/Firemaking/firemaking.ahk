; ============================================================
; firemaking.ahk
; v4 entry point + all Firemaking phases, one file (single
; bot/single loop, same shape as Motherlode). Shared framework
; classes stay in their own files.
;
; First version: assumes F5 is pressed with a full inventory of
; logs already in hand - withdrawing when NOT already full is a
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
; GoToFirePhase - verifies the green firemaking-spot marker,
; clicks it, then waits for craft-marker-1.png (the "burn logs"
; dialog) to appear.
;
; Exit: once the dialog image is found, transitions to burnLogs.
; ============================================================
class GoToFirePhase extends Phase {
    __New(markerX, markerY, markerW, markerH, markerColor, markerTolerance, searchPaddingPx, reclickCooldownMs, markerWaitTimeoutMs, craftAnchor, craftWaitTimeoutMs, craftPollKey, runMode := false) {
        super.__New("goToFire")
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
        ; Scratch timestamps are reset by WithdrawLogsPhase's per-cycle reset.
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "goToFire"

        rx1 := Max(0, this._markerX - this._searchPaddingPx)
        ry1 := Max(0, this._markerY - this._searchPaddingPx)
        rx2 := Min(A_ScreenWidth, this._markerX + this._searchPaddingPx)
        ry2 := Min(A_ScreenHeight, this._markerY + this._searchPaddingPx)

        found := ColorSearch.FindFilledBlock(rx1, ry1, rx2, ry2,
            this._markerColor, this._markerTolerance, this._markerW, this._markerH, &cx, &cy)

        if (!found) {
            waitStartedAt := ctx.Get("fireMarkerWaitStartedAt", 0)
            if (waitStartedAt == 0) {
                ctx.Set("fireMarkerWaitStartedAt", A_TickCount)
            } else if ((A_TickCount - waitStartedAt) > this._markerWaitTimeoutMs) {
                ctx.Log("GoToFirePhase: Timed out waiting for the fire marker - stopping")
                ctx.engine.Stop("Timed out waiting for fire marker")
                return "goToFire"
            }

            lastClick := ctx.Get("fireMarkerLastClickTime", 0)
            if (lastClick == 0 || (A_TickCount - lastClick) > this._reclickCooldownMs) {
                ctx.clicker.ClickSettled(ctx, this._markerX, this._markerY, this._runMode)
                ctx.Set("fireMarkerLastClickTime", A_TickCount)
                ctx.Log("GoToFirePhase: Clicked fire marker at [" this._markerX ", " this._markerY "]")
                ctx.failsafe.ResetPhaseTimer(ctx)
            }
            return "goToFire"
        }

        if (!ctx.Get("fireMarkerClicked", false)) {
            ctx.Log("GoToFirePhase: Found fire marker at [" cx ", " cy "]")
            ctx.clicker.ClickSettled(ctx, cx, cy, this._runMode)
            ctx.Set("fireMarkerClicked", true)
            ctx.failsafe.ResetPhaseTimer(ctx)
        }

        ctx.Log("GoToFirePhase: Waiting for burn dialog...")
        if (!this._craftAnchor.WaitFor(ctx.waiter, ctx.timing, this._craftPollKey, this._craftWaitTimeoutMs, &dx, &dy)) {
            ctx.Log("GoToFirePhase: Timed out waiting for burn dialog - stopping")
            ctx.engine.Stop("Timed out waiting for burn dialog")
            return "goToFire"
        }

        ctx.Log("GoToFirePhase: Burn dialog visible. Confirming.")
        return "burnLogs"
    }
}

; BurnLogsPhase/GoToBankPhase are the shared PressAndWaitEmptyPhase and
; GoToBankPhase classes from Core/SharedPhases.ahk - see Wiring below.

; ============================================================
; WithdrawLogsPhase - withdraws a multi-slot plan (each slot
; clicked its own configured number of times - currently one
; slot/one click for logs, but the same shape Smelter uses for
; multi-slot withdraws in case this ever needs more than one
; slot), then applies a settle delay before fully resetting
; per-cycle state and handing off back to goToFire.
; ============================================================
class WithdrawLogsPhase extends Phase {
    ; withdrawPlan: array of {slotIndex, clicks} in withdraw order.
    __New(bank, withdrawPlan, clickIntervalMs, settleDelayKey, nextCyclePhases, runMode := false) {
        super.__New("withdrawLogs")
        this._bank := bank
        this._withdrawPlan := withdrawPlan
        this._clickIntervalMs := clickIntervalMs
        this._settleDelayKey := settleDelayKey
        this._nextCyclePhases := nextCyclePhases
        this._runMode := runMode
    }

    ResetForNewCycle() {
        ; withdrawPlanIndex/withdrawClicksDone are reset by this phase's
        ; own completion below.
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "withdrawLogs"

        planIndex := ctx.Get("withdrawPlanIndex", 1)
        if (planIndex <= this._withdrawPlan.Length) {
            entry := this._withdrawPlan[planIndex]
            clicksDone := ctx.Get("withdrawClicksDone", 0)

            if (clicksDone >= entry["clicks"]) {
                ctx.Set("withdrawPlanIndex", planIndex + 1)
                ctx.Set("withdrawClicksDone", 0)
                return "withdrawLogs"
            }

            lastClick := ctx.Get("withdrawLastClickTime", 0)
            if (lastClick != 0 && (A_TickCount - lastClick) < this._clickIntervalMs)
                return "withdrawLogs"

            this._bank.WithdrawSlot(entry["slotIndex"], &x, &y)
            ctx.clicker.ClickSettled(ctx, x, y, this._runMode)
            ctx.Set("withdrawClicksDone", clicksDone + 1)
            ctx.Set("withdrawLastClickTime", A_TickCount)
            ctx.Log("WithdrawLogsPhase: Clicked bank slot " entry["slotIndex"] " at [" x ", " y "] (" clicksDone + 1 "/" entry["clicks"] ")")
            ctx.failsafe.ResetPhaseTimer(ctx)
            return "withdrawLogs"
        }

        ; One-time settle delay before handing off - the fire marker may not
        ; be rendered/stable in the client immediately after withdrawing
        ; (character/camera still catching up), same bug class fixed
        ; repeatedly in Motherlode. Tune postWithdrawSettleDelayMs live.
        ctx.waiter.After(ctx.timing, this._settleDelayKey)

        ctx.Log("WithdrawLogsPhase: Withdraw plan complete. Handing off to fire phase.")

        ctx.Set("fireMarkerWaitStartedAt", 0)
        ctx.Set("fireMarkerLastClickTime", 0)
        ctx.Set("fireMarkerClicked", false)
        ctx.Set("keyPressed", false)
        ctx.Set("bankMarkerWaitStartedAt", 0)
        ctx.Set("bankMarkerLastClickTime", 0)
        ctx.Set("bankMarkerClicked", false)
        ctx.Set("withdrawPlanIndex", 1)
        ctx.Set("withdrawClicksDone", 0)
        ctx.Set("withdrawLastClickTime", 0)
        for phase in this._nextCyclePhases
            phase.ResetForNewCycle()

        return "goToFire"
    }
}

; ============================================================
; Wiring
; ============================================================

schema := Map(
    "runnerTickMs", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutFire", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutBank", Map("section", "Tunables", "type", "int"),
    "colorTolerance", Map("section", "Tunables", "type", "int"),
    "fireMarkerX", Map("section", "Tunables", "type", "int"),
    "fireMarkerY", Map("section", "Tunables", "type", "int"),
    "fireMarkerW", Map("section", "Tunables", "type", "int"),
    "fireMarkerH", Map("section", "Tunables", "type", "int"),
    "fireMarkerColor", Map("section", "Tunables", "type", "color"),
    "fireMarkerTolerance", Map("section", "Tunables", "type", "int"),
    "fireMarkerSearchPaddingPx", Map("section", "Tunables", "type", "int"),
    "fireMarkerReclickCooldownMs", Map("section", "Tunables", "type", "int"),
    "fireMarkerWaitTimeoutMs", Map("section", "Tunables", "type", "int"),
    "craftMarkerAnchorX", Map("section", "Tunables", "type", "int"),
    "craftMarkerAnchorY", Map("section", "Tunables", "type", "int"),
    "craftMarkerImageW", Map("section", "Tunables", "type", "int"),
    "craftMarkerImageH", Map("section", "Tunables", "type", "int"),
    "craftMarkerSearchPaddingPx", Map("section", "Tunables", "type", "int"),
    "craftMarkerWaitTimeoutMs", Map("section", "Tunables", "type", "int"),
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
    "withdrawClickIntervalMs", Map("section", "Tunables", "type", "int"),
    "runMode", Map("section", "Settings", "type", "int"),
    "indicatorSlot", Map("section", "Settings", "type", "int")
)
timingSchema := Map(
    "clickSettle", Map("section", "Tunables", "baseMsKey", "clickSettleMs", "jitterPercentKey", "clickSettleJitterPercent"),
    "ctrlHoldSettle", Map("section", "Tunables", "baseMsKey", "ctrlHoldSettleMs", "jitterPercentKey", "clickSettleJitterPercent"),
    "craftMarkerPoll", Map("section", "Tunables", "baseMsKey", "craftMarkerPollMs"),
    "spacePressSettle", Map("section", "Tunables", "baseMsKey", "spacePressSettleMs"),
    "bankOpenPoll", Map("section", "Tunables", "baseMsKey", "bankOpenPollMs"),
    "postWithdrawSettle", Map("section", "Tunables", "baseMsKey", "postWithdrawSettleDelayMs")
)

iniPath := A_ScriptDir "\..\..\Config\auto-firemaking-v2.ini"
botConfig := Config(iniPath, schema, timingSchema)
botConfig.Load()

botLogger := Logger(A_ScriptDir "\..\..\logs\auto-firemaking-v4-debug.log")
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
; Motherlode's calibration for this window.
inventoryLayout := Map("firstX", 2099, "firstY", 801, "cols", 4, "rows", 7, "slotW", 72, "slotH", 64, "gapX", 12, "gapY", 8)
ctx.inventory := Inventory(inventoryLayout)
fullGate := SlotGate(botConfig.Get("indicatorSlot"), botConfig.Get("colorTolerance"), ctx.inventory)
ctx.inventory.SetFullGate(fullGate)
ctx.inventory.SetEmptyGate(NotGate(fullGate))

; craft-marker-1.png - shown once the "burn logs" dialog opens.
craftImagePath := A_ScriptDir "\..\..\Images\craft-marker-1.png"
craftImageRegion := Map(
    "x1", botConfig.Get("craftMarkerAnchorX") - botConfig.Get("craftMarkerSearchPaddingPx"),
    "y1", botConfig.Get("craftMarkerAnchorY") - botConfig.Get("craftMarkerSearchPaddingPx"),
    "x2", botConfig.Get("craftMarkerAnchorX") + botConfig.Get("craftMarkerImageW") + botConfig.Get("craftMarkerSearchPaddingPx"),
    "y2", botConfig.Get("craftMarkerAnchorY") + botConfig.Get("craftMarkerImageH") + botConfig.Get("craftMarkerSearchPaddingPx")
)
craftAnchor := ImageAnchor(craftImageRegion, craftImagePath, botConfig.Get("craftMarkerImageW"), botConfig.Get("craftMarkerImageH"))

; deposit-default.png - used only to confirm the bank interface opened;
; never clicked as "deposit all" in this bot.
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
; chestAnchor is unused by this bot (GoToBankPhase clicks the blue marker
; directly via ColorSearch, not through Bank.OpenChest's own anchor) -
; OpenChest is still reused for its click-and-report shape.
botBank := Bank(bankOpenAnchor, bankOpenAnchor, botClicker, bankSlotLayout)

botGoToFirePhase := GoToFirePhase(
    botConfig.Get("fireMarkerX"), botConfig.Get("fireMarkerY"),
    botConfig.Get("fireMarkerW"), botConfig.Get("fireMarkerH"),
    botConfig.Get("fireMarkerColor"), botConfig.Get("fireMarkerTolerance"),
    botConfig.Get("fireMarkerSearchPaddingPx"), botConfig.Get("fireMarkerReclickCooldownMs"),
    botConfig.Get("fireMarkerWaitTimeoutMs"), craftAnchor,
    botConfig.Get("craftMarkerWaitTimeoutMs"), "craftMarkerPoll", botConfig.Get("runMode")
)

botBurnLogsPhase := PressAndWaitEmptyPhase("burnLogs", botKeyAction, "space", "spacePressSettle", "goToBank")

botGoToBankPhase := GoToBankPhase(
    botConfig.Get("bankMarkerX"), botConfig.Get("bankMarkerY"),
    botConfig.Get("bankMarkerW"), botConfig.Get("bankMarkerH"),
    botConfig.Get("bankMarkerColor"), botConfig.Get("bankMarkerTolerance"),
    botConfig.Get("bankMarkerSearchPaddingPx"), botConfig.Get("bankMarkerReclickCooldownMs"),
    botConfig.Get("bankMarkerWaitTimeoutMs"), bankOpenAnchor,
    botConfig.Get("bankOpenWaitTimeoutMs"), "bankOpenPoll", "withdrawLogs", botConfig.Get("runMode")
)

nextCyclePhases := [botGoToFirePhase, botBurnLogsPhase, botGoToBankPhase]

; Withdraw plan: ordered list of {slotIndex, clicks}, built from .ini so the
; slot count/indices/click counts are all tunable, not hardcoded - same
; shape Smelter uses for its own (currently larger) withdraw plan.
withdrawPlan := []
loop botConfig.Get("withdrawSlotCount") {
    n := A_Index
    withdrawPlan.Push(Map("slotIndex", botConfig.Get("withdrawSlot" n "Index"), "clicks", botConfig.Get("withdrawSlot" n "Clicks")))
}

botWithdrawLogsPhase := WithdrawLogsPhase(
    botBank, withdrawPlan, botConfig.Get("withdrawClickIntervalMs"), "postWithdrawSettle",
    nextCyclePhases, botConfig.Get("runMode")
)
nextCyclePhases.Push(botWithdrawLogsPhase)

botEngine := Engine(ctx, botConfig.Get("runnerTickMs"))
ctx.engine := botEngine
botEngine.AddPhase(botGoToFirePhase, botConfig.Get("phaseTimeoutFire"))
botEngine.AddPhase(botBurnLogsPhase, botConfig.Get("phaseTimeoutFire"))
botEngine.AddPhase(botGoToBankPhase, botConfig.Get("phaseTimeoutBank"))
botEngine.AddPhase(botWithdrawLogsPhase, botConfig.Get("phaseTimeoutBank"))

F5:: botEngine.Start("goToFire")
F6:: {
    botEngine.Stop("Stopped (F6)")
    botOverlay.Clear()
}
