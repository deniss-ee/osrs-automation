; ============================================================
; motherlode-fixed.ahk
; Stand-still Motherlode variant: the character never moves from
; one tile, with exactly two known fixed-position veins around it.
; No region search/walking/TargetLock needed for mining - just two
; fixed-point color checks. Hopper/bank/return steps are modeled
; closely on Bots/Motherlode/motherlode.ahk (a separate bot/file -
; this one never touches that bot's code or config).
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

; AHK v2 defaults Click/MouseMove/PixelSearch to "Client" coords
; (relative to the focused window). Every coordinate here is
; absolute screen space.
CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

#Include ..\..\Core\Engine.ahk
#Include ..\..\Core\EngineContext.ahk
#Include ..\..\Core\FailSafe.ahk
#Include ..\..\Core\Phase.ahk
#Include ..\..\Timing\Waiter.ahk
#Include ..\..\Detection\ColorSearch.ahk
#Include ..\..\Detection\Telemetry.ahk
#Include ..\..\Detection\StaticAnchor.ahk
#Include ..\..\Interfaces\Inventory.ahk
#Include ..\..\Actions\Humanizer.ahk
#Include ..\..\Actions\Click.ahk
#Include ..\..\Config\Config.ahk
#Include ..\..\Diagnostics\Logger.ahk
#Include ..\..\Diagnostics\WindowFocus.ahk
#Include ..\..\Diagnostics\Overlay.ahk

; ============================================================
; MinePhase - two fixed-position veins, no walking/searching.
;
; While a vein is marked active (activeVein scratch key set), only
; that vein's fixed point is checked - still active means the
; ongoing mining action continues on its own, no re-click needed.
; Once it's confirmed gone, activeVein clears and BOTH points are
; checked again on the same tick (a switch shouldn't cost an idle
; poll first).
;
; "Never abandon a still-active vein just because the other lit up"
; falls out naturally from only ever checking the active vein's own
; point while one is locked in - the other vein's state is never
; even read until the current one depletes.
; ============================================================
class MinePhase extends Phase {
    __New(veinA, veinB, blockW, blockH, tolerance, runMode := false) {
        super.__New("mine")
        this._veinA := veinA   ; {x, y, color}
        this._veinB := veinB   ; {x, y, color}
        this._blockW := blockW
        this._blockH := blockH
        this._tolerance := tolerance
        this._runMode := runMode
    }

    ResetForNewCycle() {
        ; activeVein is cleared explicitly wherever a full cycle resets
        ; (see the inventory-full transition below), not here - this
        ; phase has no TargetLock/stability state to reset.
    }

    _VeinActive(vein) {
        hw := this._blockW // 2
        hh := this._blockH // 2
        return ColorSearch.FindFilledBlock(
            vein["x"] - hw, vein["y"] - hh, vein["x"] + hw, vein["y"] + hh,
            vein["color"], this._tolerance, this._blockW, this._blockH, &cx, &cy)
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "mine"

        if (ctx.inventory.IsFull()) {
            ctx.Log("MinePhase: Inventory full, transitioning to depositBank")
            ctx.Set("activeVein", "")
            ctx.Set("depositPreDelayApplied", false)
            ctx.Set("returnClicked", false)
            ctx.Set("returnWaitStartedAt", 0)
            return "depositBank"
        }

        active := ctx.Get("activeVein", "")

        if (active != "") {
            vein := active = "A" ? this._veinA : this._veinB
            if (this._VeinActive(vein))
                return "mine"   ; still mining, ongoing action continues on its own

            ctx.Log("MinePhase: Vein " active " depleted. Checking for another.")
            ctx.Set("activeVein", "")
            active := ""
        }

        ; No vein currently locked in - check both fixed points fresh.
        if (this._VeinActive(this._veinA)) {
            ctx.clicker.ClickSettled(ctx, this._veinA["x"], this._veinA["y"], this._runMode)
            ctx.Set("activeVein", "A")
            ctx.Log("MinePhase: Clicked vein A at [" this._veinA["x"] ", " this._veinA["y"] "]")
            ctx.failsafe.ResetPhaseTimer(ctx)
        } else if (this._VeinActive(this._veinB)) {
            ctx.clicker.ClickSettled(ctx, this._veinB["x"], this._veinB["y"], this._runMode)
            ctx.Set("activeVein", "B")
            ctx.Log("MinePhase: Clicked vein B at [" this._veinB["x"] ", " this._veinB["y"] "]")
            ctx.failsafe.ResetPhaseTimer(ctx)
        }

        return "mine"
    }
}

; ============================================================
; DepositBankPhase - finds and clicks the deposit container (a
; magenta 0xFF00FF marker in a small fixed region, since the
; character never moves from its mining tile), waits for the
; deposit box's "Deposit All" button image to appear, then clicks
; it. Modeled closely on Bots/Motherlode/motherlode.ahk's own
; DepositBankPhase.
;
; Exit: once deposited, transitions to returnToMine. Stops the
; engine cleanly if the deposit box image never appears.
; ============================================================
class DepositBankPhase extends Phase {
    __New(color, tolerance, reqW, reqH, markerX, markerY, searchPaddingPx, depositAnchor, imageWaitTimeoutMs, imagePollKey, preClickDelayKey, runMode := false) {
        super.__New("depositBank")
        this._color := color
        this._tolerance := tolerance
        this._reqW := reqW
        this._reqH := reqH
        this._markerX := markerX
        this._markerY := markerY
        this._searchPaddingPx := searchPaddingPx
        this._depositAnchor := depositAnchor   ; an ImageAnchor for deposit-motherlode.png
        this._imageWaitTimeoutMs := imageWaitTimeoutMs
        this._imagePollKey := imagePollKey
        this._preClickDelayKey := preClickDelayKey
        this._runMode := runMode
    }

    ResetForNewCycle() {
        ; depositPreDelayApplied is reset by MinePhase's inventory-full
        ; transition, alongside the other per-cycle scratch state.
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "depositBank"

        ; One-time settle delay BEFORE searching, not after - matches
        ; the original Motherlode's DepositBankPhase reasoning.
        if (!ctx.Get("depositPreDelayApplied", false)) {
            ctx.waiter.After(ctx.timing, this._preClickDelayKey)
            ctx.Set("depositPreDelayApplied", true)
        }

        rx1 := this._markerX - this._searchPaddingPx
        ry1 := this._markerY - this._searchPaddingPx
        rx2 := this._markerX + this._searchPaddingPx
        ry2 := this._markerY + this._searchPaddingPx

        found := ColorSearch.FindFilledBlock(rx1, ry1, rx2, ry2,
            this._color, this._tolerance, this._reqW, this._reqH, &cx, &cy)

        if (!found) {
            ctx.Log("DepositBankPhase: Cannot see deposit container!")
            return "depositBank"
        }

        ctx.Log("DepositBankPhase: Clicked deposit container at [" cx ", " cy "]")
        ctx.clicker.ClickSettled(ctx, cx, cy, this._runMode)
        ctx.failsafe.ResetPhaseTimer(ctx)

        ctx.Log("DepositBankPhase: Waiting for deposit box to open...")
        if (!this._depositAnchor.WaitFor(ctx.waiter, ctx.timing, this._imagePollKey, this._imageWaitTimeoutMs, &dx, &dy)) {
            ctx.Log("DepositBankPhase: Timed out waiting for deposit box - stopping")
            ctx.engine.Stop("Timed out waiting for deposit box")
            return "depositBank"
        }

        ctx.clicker.ClickSettled(ctx, dx, dy, this._runMode)
        ctx.Log("DepositBankPhase: Deposited all - returning to mine")
        return "returnToMine"
    }
}

; ============================================================
; ReturnToMinePhase - one click back to the mining tile, then
; waits for either vein's fixed point to show its color again,
; confirming arrival. Collapses the original Motherlode's 2-stage
; walk-back into one phase, since here it's a single click, not a
; multi-waypoint walk.
;
; Exit: transitions back to mine once a vein is detected. Stops
; the engine cleanly if neither vein appears before the timeout.
; ============================================================
class ReturnToMinePhase extends Phase {
    __New(clickX, clickY, veinA, veinB, blockW, blockH, tolerance, veinPollKey, waitTimeoutMs, nextCyclePhases, runMode := false) {
        super.__New("returnToMine")
        this._clickX := clickX
        this._clickY := clickY
        this._veinA := veinA
        this._veinB := veinB
        this._blockW := blockW
        this._blockH := blockH
        this._tolerance := tolerance
        this._veinPollKey := veinPollKey
        this._waitTimeoutMs := waitTimeoutMs
        this._nextCyclePhases := nextCyclePhases
        this._runMode := runMode
    }

    ResetForNewCycle() {
        ; returnClicked/returnWaitStartedAt are reset by this phase's own
        ; completion below, alongside every other phase's per-cycle state.
    }

    _VeinActive(vein) {
        hw := this._blockW // 2
        hh := this._blockH // 2
        return ColorSearch.FindFilledBlock(
            vein["x"] - hw, vein["y"] - hh, vein["x"] + hw, vein["y"] + hh,
            vein["color"], this._tolerance, this._blockW, this._blockH, &cx, &cy)
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "returnToMine"

        if (!ctx.Get("returnClicked", false)) {
            ctx.clicker.ClickSettled(ctx, this._clickX, this._clickY, this._runMode)
            ctx.Set("returnClicked", true)
            ctx.Log("ReturnToMinePhase: Clicked return point at [" this._clickX ", " this._clickY "]")
            ctx.failsafe.ResetPhaseTimer(ctx)
            return "returnToMine"
        }

        if (this._VeinActive(this._veinA) || this._VeinActive(this._veinB)) {
            ctx.Log("ReturnToMinePhase: Arrived - vein visible. Resuming mining.")

            ; Full per-cycle reset before handing off to "mine".
            ctx.Set("activeVein", "")
            ctx.Set("depositPreDelayApplied", false)
            ctx.Set("returnClicked", false)
            ctx.Set("returnWaitStartedAt", 0)
            for phase in this._nextCyclePhases
                phase.ResetForNewCycle()

            return "mine"
        }

        waitStartedAt := ctx.Get("returnWaitStartedAt", 0)
        if (waitStartedAt == 0) {
            ctx.Set("returnWaitStartedAt", A_TickCount)
        } else if ((A_TickCount - waitStartedAt) > this._waitTimeoutMs) {
            ctx.Log("ReturnToMinePhase: Timed out waiting for a vein to reappear - stopping")
            ctx.engine.Stop("Timed out waiting for vein after return click")
            return "returnToMine"
        }

        ctx.waiter.After(ctx.timing, this._veinPollKey)
        return "returnToMine"
    }
}

; ============================================================
; Wiring
; ============================================================

schema := Map(
    "runnerTickMs", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutMine", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutBank", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutReturn", Map("section", "Tunables", "type", "int"),
    "veinTolerance", Map("section", "Tunables", "type", "int"),
    "veinAX", Map("section", "Tunables", "type", "int"),
    "veinAY", Map("section", "Tunables", "type", "int"),
    "veinAColor", Map("section", "Tunables", "type", "color"),
    "veinBX", Map("section", "Tunables", "type", "int"),
    "veinBY", Map("section", "Tunables", "type", "int"),
    "veinBColor", Map("section", "Tunables", "type", "color"),
    "veinBlockW", Map("section", "Tunables", "type", "int"),
    "veinBlockH", Map("section", "Tunables", "type", "int"),
    "depositColor", Map("section", "Tunables", "type", "color"),
    "depositTolerance", Map("section", "Tunables", "type", "int"),
    "depositBlockW", Map("section", "Tunables", "type", "int"),
    "depositBlockH", Map("section", "Tunables", "type", "int"),
    "depositMarkerX", Map("section", "Tunables", "type", "int"),
    "depositMarkerY", Map("section", "Tunables", "type", "int"),
    "depositSearchPaddingPx", Map("section", "Tunables", "type", "int"),
    "depositPreClickDelayMs", Map("section", "Tunables", "type", "int"),
    "depositImageAnchorX", Map("section", "Tunables", "type", "int"),
    "depositImageAnchorY", Map("section", "Tunables", "type", "int"),
    "depositImageSearchPaddingPx", Map("section", "Tunables", "type", "int"),
    "depositImageWaitTimeoutMs", Map("section", "Tunables", "type", "int"),
    "depositImagePollMs", Map("section", "Tunables", "type", "int"),
    "returnClickX", Map("section", "Tunables", "type", "int"),
    "returnClickY", Map("section", "Tunables", "type", "int"),
    "returnVeinPollMs", Map("section", "Tunables", "type", "int"),
    "returnWaitTimeoutMs", Map("section", "Tunables", "type", "int"),
    "clickSettleMs", Map("section", "Tunables", "type", "int"),
    "clickSettleJitterPercent", Map("section", "Tunables", "type", "int"),
    "ctrlHoldSettleMs", Map("section", "Tunables", "type", "int"),
    "runMode", Map("section", "Settings", "type", "int"),
    "indicatorSlot", Map("section", "Settings", "type", "int")
)
timingSchema := Map(
    "clickSettle", Map("section", "Tunables", "baseMsKey", "clickSettleMs", "jitterPercentKey", "clickSettleJitterPercent"),
    "ctrlHoldSettle", Map("section", "Tunables", "baseMsKey", "ctrlHoldSettleMs", "jitterPercentKey", "clickSettleJitterPercent"),
    "depositPreClickDelay", Map("section", "Tunables", "baseMsKey", "depositPreClickDelayMs"),
    "depositImagePoll", Map("section", "Tunables", "baseMsKey", "depositImagePollMs"),
    "returnVeinPoll", Map("section", "Tunables", "baseMsKey", "returnVeinPollMs")
)

iniPath := A_ScriptDir "\..\..\Config\auto-motherlode-fixed.ini"
botConfig := Config(iniPath, schema, timingSchema)
botConfig.Load()

botLogger := Logger(A_ScriptDir "\..\..\logs\auto-motherlode-fixed-v4-debug.log")
botHumanizer := Humanizer(false)
botClicker := Clicker(botHumanizer)
botFailsafe := FailSafe(botLogger)
botWaiter := Waiter((baseMs, jitterPercent) => botHumanizer.Jitter(baseMs, jitterPercent))
botWindowFocus := WindowFocus()
botOverlay := Overlay(8, 10, 10)

ctx := EngineContext(botConfig, botLogger, botClicker, botFailsafe, botWaiter, botWindowFocus, botOverlay)

; Inventory layout is a fixed property of this client window (not a
; game-state tunable), so it's a hardcoded constant, not an .ini key -
; same values as the original Motherlode bot (same client window).
inventoryLayout := Map("firstX", 2099, "firstY", 801, "cols", 4, "rows", 7, "slotW", 72, "slotH", 64, "gapX", 12, "gapY", 8)
ctx.inventory := Inventory(inventoryLayout)
; Full = indicatorSlot (28, the last slot) alone occupied - unlike the
; original hopper-based Motherlode bot, this bot deposits into a
; bank-style deposit box that accepts any item, so there's no "gem the
; container won't take" case requiring a second slot to guard against.
indicatorGate := SlotGate(botConfig.Get("indicatorSlot"), botConfig.Get("veinTolerance"), ctx.inventory)
ctx.inventory.SetFullGate(indicatorGate)
ctx.inventory.SetEmptyGate(NotGate(indicatorGate))

veinA := Map("x", botConfig.Get("veinAX"), "y", botConfig.Get("veinAY"), "color", botConfig.Get("veinAColor"))
veinB := Map("x", botConfig.Get("veinBX"), "y", botConfig.Get("veinBY"), "color", botConfig.Get("veinBColor"))

; Deposit box "Deposit All" button image anchor - the search region is
; the calibrated anchor padded by depositImageSearchPaddingPx.
; deposit-motherlode.png is 80x72px (confirmed on disk, same image the
; original Motherlode bot uses).
depositImagePath := A_ScriptDir "\..\..\Images\deposit-motherlode.png"
depositImageRegion := Map(
    "x1", botConfig.Get("depositImageAnchorX") - botConfig.Get("depositImageSearchPaddingPx"),
    "y1", botConfig.Get("depositImageAnchorY") - botConfig.Get("depositImageSearchPaddingPx"),
    "x2", botConfig.Get("depositImageAnchorX") + 80 + botConfig.Get("depositImageSearchPaddingPx"),
    "y2", botConfig.Get("depositImageAnchorY") + 72 + botConfig.Get("depositImageSearchPaddingPx")
)
depositAnchor := ImageAnchor(depositImageRegion, depositImagePath, 80, 72)

botDepositBankPhase := DepositBankPhase(
    botConfig.Get("depositColor"), botConfig.Get("depositTolerance"),
    botConfig.Get("depositBlockW"), botConfig.Get("depositBlockH"),
    botConfig.Get("depositMarkerX"), botConfig.Get("depositMarkerY"), botConfig.Get("depositSearchPaddingPx"),
    depositAnchor, botConfig.Get("depositImageWaitTimeoutMs"), "depositImagePoll",
    "depositPreClickDelay", botConfig.Get("runMode")
)

nextCyclePhases := [botDepositBankPhase]

botReturnToMinePhase := ReturnToMinePhase(
    botConfig.Get("returnClickX"), botConfig.Get("returnClickY"),
    veinA, veinB, botConfig.Get("veinBlockW"), botConfig.Get("veinBlockH"), botConfig.Get("veinTolerance"),
    "returnVeinPoll", botConfig.Get("returnWaitTimeoutMs"), nextCyclePhases, botConfig.Get("runMode")
)
nextCyclePhases.Push(botReturnToMinePhase)

botMinePhase := MinePhase(
    veinA, veinB, botConfig.Get("veinBlockW"), botConfig.Get("veinBlockH"), botConfig.Get("veinTolerance"),
    botConfig.Get("runMode")
)

botEngine := Engine(ctx, botConfig.Get("runnerTickMs"))
ctx.engine := botEngine
botEngine.AddPhase(botMinePhase, botConfig.Get("phaseTimeoutMine"))
botEngine.AddPhase(botDepositBankPhase, botConfig.Get("phaseTimeoutBank"))
botEngine.AddPhase(botReturnToMinePhase, botConfig.Get("phaseTimeoutReturn"))

F5:: botEngine.Start("mine")
F6:: {
    botEngine.Stop("Stopped (F6)")
    botOverlay.Clear()
}
