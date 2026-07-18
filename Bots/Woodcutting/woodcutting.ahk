; ============================================================
; woodcutting.ahk
; v4 entry point + all Woodcutting phases, one file (single
; bot/single loop, same shape as Motherlode/Firemaking).
;
; Loop: full-screen search for a tree overlay block, chop it until
; it depletes (color no longer matches) or the inventory is full,
; re-acquiring a new tree on depletion (same acquire/track shape as
; Motherlode's ClearRedPhase). Once full, full-screen search for the
; deposit-bank marker, click it, wait for the deposit interface,
; click deposit-all, click a fixed post-deposit point, settle, then
; resume chopping.
;
; Isolation: reads/writes only this bot's own Config/ and logs/.
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
#Include ..\..\Timing\Waiter.ahk
#Include ..\..\Detection\ColorSearch.ahk
#Include ..\..\Detection\TargetLock.ahk
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
; ChopWoodPhase - full-screen acquire/track/depleted loop against a
; single tree-overlay color, mirroring Motherlode's ClearRedPhase
; shape (one color, not MinePhase's two-vein-color picker). Exits
; to depositBank once the inventory's indicator slot is occupied.
; ============================================================
class ChopWoodPhase extends Phase {
    __New(treeColor, tolerance, reqW, reqH, scanBottomUp, trackBoxRadiusPx,
          stableTicksRequired, moveTolerancePx, clickCooldownMs,
          walkReclickTimeoutMs, nextCyclePhases, runMode := false) {
        super.__New("chopWood")
        this._treeColor := treeColor
        this._tolerance := tolerance
        this._reqW := reqW
        this._reqH := reqH
        this._scanBottomUp := scanBottomUp
        this._trackBoxRadiusPx := trackBoxRadiusPx
        this._clickCooldownMs := clickCooldownMs
        this._walkReclickTimeoutMs := walkReclickTimeoutMs
        this._nextCyclePhases := nextCyclePhases
        this._runMode := runMode
        this._lock := TargetLock(stableTicksRequired, moveTolerancePx)
    }

    ; Called on the depositBank->chopWood transition so a fresh cycle
    ; starts this phase's TargetLock clean, not with a stale streak.
    ResetForNewCycle() {
        this._lock.Reset()
    }

    Run(ctx) {
        ; Window-focus guard temporarily disabled - was blocking tree
        ; search/clicks even while RuneLite appeared focused. Root cause
        ; not yet diagnosed; re-enable once WindowFocus's WinActive match
        ; is confirmed reliable for this client/launcher setup.
        ; if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
        ;     return "chopWood"

        if (ctx.inventory.IsFull()) {
            ctx.Log("ChopWoodPhase: Inventory full. Heading to bank.")
            ctx.Set("treeHasTarget", false)
            ctx.Set("treeTargetX", 0)
            ctx.Set("treeTargetY", 0)
            ctx.Set("treeLastClickTime", 0)
            for phase in this._nextCyclePhases
                phase.ResetForNewCycle()
            return "depositBank"
        }

        if (!ctx.Get("treeHasTarget", false))
            return this._Acquire(ctx)
        return this._Track(ctx)
    }

    ; Mode 1: no target locked - search the whole screen for the tree
    ; overlay color. Not found just means no tree is visible yet.
    _Acquire(ctx) {
        found := ColorSearch.FindFilledBlock(0, 0, A_ScreenWidth, A_ScreenHeight,
            this._treeColor, this._tolerance, this._reqW, this._reqH, &tx, &ty,
            this._scanBottomUp)

        if (!found)
            return "chopWood"

        ctx.Set("treeHasTarget", true)
        ctx.Set("treeTargetX", tx)
        ctx.Set("treeTargetY", ty)
        ctx.Set("treeLastClickTime", 0)
        this._lock.Reset()
        ctx.Log("ChopWoodPhase: Found new tree at [" tx ", " ty "]")
        ctx.failsafe.ResetPhaseTimer(ctx)
        return "chopWood"
    }

    ; Mode 2: target locked - re-search a narrowed box around the last
    ; known position. found=false (color no longer matches) means the
    ; tree is depleted or lost - fall back to a fresh full-screen search.
    _Track(ctx) {
        lastX := ctx.Get("treeTargetX", 0)
        lastY := ctx.Get("treeTargetY", 0)

        rx1 := Max(0, lastX - this._trackBoxRadiusPx)
        ry1 := Max(0, lastY - this._trackBoxRadiusPx)
        rx2 := Min(A_ScreenWidth, lastX + this._trackBoxRadiusPx)
        ry2 := Min(A_ScreenHeight, lastY + this._trackBoxRadiusPx)

        nx := 0, ny := 0
        found := ColorSearch.FindFilledBlock(rx1, ry1, rx2, ry2,
            this._treeColor, this._tolerance, this._reqW, this._reqH, &nx, &ny,
            this._scanBottomUp, lastX, lastY)
        this._lock.Observe(found, nx, ny, &outX, &outY)

        if (!found) {
            ctx.Log("ChopWoodPhase: Tree depleted or lost. Finding new tree.")
            ctx.Set("treeHasTarget", false)
            ctx.Set("treeTargetX", 0)
            ctx.Set("treeTargetY", 0)
            return "chopWood"
        }

        ctx.Set("treeTargetX", outX)
        ctx.Set("treeTargetY", outY)

        if (this._lock.IsStable()) {
            lastClick := ctx.Get("treeLastClickTime", 0)
            if ((A_TickCount - lastClick) > this._clickCooldownMs) {
                ctx.clicker.ClickSettled(ctx, outX, outY, this._runMode)
                ctx.Set("treeLastClickTime", A_TickCount)
                ctx.Log("ChopWoodPhase: Clicked stable tree at [" outX ", " outY "]")
                ctx.failsafe.ResetPhaseTimer(ctx)
            }
        } else {
            lastClick := ctx.Get("treeLastClickTime", 0)
            if (lastClick == 0 || (A_TickCount - lastClick) > this._walkReclickTimeoutMs) {
                ctx.clicker.ClickSettled(ctx, outX, outY, this._runMode)
                ctx.Set("treeLastClickTime", A_TickCount)
                ctx.Log("ChopWoodPhase: Initial/re-click on tree at [" outX ", " outY "]")
                ctx.failsafe.ResetPhaseTimer(ctx)
            }
        }

        return "chopWood"
    }
}

; ============================================================
; DepositBankPhase - full-screen search for the deposit-bank
; marker, click it, wait for the deposit interface, click deposit
; all, then (as an internal second stage under the same phase name)
; click a fixed post-deposit point and settle before handing back to
; chopWood. Bot-specific rather than the shared GoToBankPhase, since
; the bank marker's position isn't fixed relative to a calibrated
; point - the player's position varies tree to tree, same reasoning
; as Motherlode's own inline DepositBankPhase.
; ============================================================
class DepositBankPhase extends Phase {
    __New(bankColor, tolerance, reqW, reqH, scanBottomUp,
          depositAnchor, imageWaitTimeoutMs, imagePollKey,
          finalClickX, finalClickY, postDepositSettleKey,
          nextCyclePhases, runMode := false) {
        super.__New("depositBank")
        this._bankColor := bankColor
        this._tolerance := tolerance
        this._reqW := reqW
        this._reqH := reqH
        this._scanBottomUp := scanBottomUp
        this._depositAnchor := depositAnchor
        this._imageWaitTimeoutMs := imageWaitTimeoutMs
        this._imagePollKey := imagePollKey
        this._finalClickX := finalClickX
        this._finalClickY := finalClickY
        this._postDepositSettleKey := postDepositSettleKey
        this._nextCyclePhases := nextCyclePhases
        this._runMode := runMode
    }

    ResetForNewCycle() {
        ; bankStage/bankLastClickTime are reset by this phase's own
        ; stage-2 completion below.
    }

    Run(ctx) {
        ; Window-focus guard temporarily disabled - see ChopWoodPhase.Run's
        ; matching note.
        ; if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
        ;     return "depositBank"

        stage := ctx.Get("bankStage", 1)
        if (stage == 1)
            return this._Stage1_FindAndClickBank(ctx)
        return this._Stage2_ClickFixedPointAndSettle(ctx)
    }

    ; Stage 1: full-screen search for the deposit-bank marker, click
    ; it, wait for the deposit interface to open, click deposit-all.
    _Stage1_FindAndClickBank(ctx) {
        found := ColorSearch.FindFilledBlock(0, 0, A_ScreenWidth, A_ScreenHeight,
            this._bankColor, this._tolerance, this._reqW, this._reqH, &cx, &cy,
            this._scanBottomUp)

        if (!found) {
            ctx.Log("DepositBankPhase: Cannot see deposit marker!")
            return "depositBank"
        }

        ctx.Log("DepositBankPhase: Clicked deposit marker at [" cx ", " cy "]")
        ctx.clicker.ClickSettled(ctx, cx, cy, this._runMode)
        ctx.failsafe.ResetPhaseTimer(ctx)

        ctx.Log("DepositBankPhase: Waiting for deposit box to open...")
        if (!this._depositAnchor.WaitFor(ctx.waiter, ctx.timing, this._imagePollKey,
                this._imageWaitTimeoutMs, &dx, &dy)) {
            ctx.Log("DepositBankPhase: Timed out waiting for deposit box - stopping")
            ctx.engine.Stop("Timed out waiting for deposit box")
            return "depositBank"
        }

        ctx.clicker.ClickSettled(ctx, dx, dy, this._runMode)
        ctx.Log("DepositBankPhase: Deposited all. Moving to final approach click.")
        ctx.Set("bankStage", 2)
        ctx.Set("bankLastClickTime", 0)
        ctx.failsafe.ResetPhaseTimer(ctx)
        return "depositBank"
    }

    ; Stage 2: click the fixed point once, wait the configurable
    ; settle ms, then fully reset per-cycle state and hand off to
    ; chopWood.
    _Stage2_ClickFixedPointAndSettle(ctx) {
        lastClick := ctx.Get("bankLastClickTime", 0)
        if (lastClick == 0) {
            ctx.clicker.ClickSettled(ctx, this._finalClickX, this._finalClickY, this._runMode)
            ctx.Set("bankLastClickTime", A_TickCount)
            ctx.Log("DepositBankPhase: Clicked final point at [" this._finalClickX ", " this._finalClickY "]")
            ctx.failsafe.ResetPhaseTimer(ctx)
            ctx.waiter.After(ctx.timing, this._postDepositSettleKey)
        }

        ctx.Log("DepositBankPhase: Settle wait complete. Handing off to chopWood.")

        ctx.Set("treeHasTarget", false)
        ctx.Set("treeTargetX", 0)
        ctx.Set("treeTargetY", 0)
        ctx.Set("treeLastClickTime", 0)
        ctx.Set("bankStage", 1)
        ctx.Set("bankLastClickTime", 0)
        for phase in this._nextCyclePhases
            phase.ResetForNewCycle()

        return "chopWood"
    }
}

; ============================================================
; Wiring
; ============================================================

schema := Map(
    "runnerTickMs", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutChopWood", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutBank", Map("section", "Tunables", "type", "int"),
    "colorTolerance", Map("section", "Tunables", "type", "int"),
    "targetLockMoveTolerancePx", Map("section", "Tunables", "type", "int"),
    "treeColor", Map("section", "Tunables", "type", "color"),
    "treeBlockW", Map("section", "Tunables", "type", "int"),
    "treeBlockH", Map("section", "Tunables", "type", "int"),
    "treeScanBottomUp", Map("section", "Tunables", "type", "int"),
    "treeTrackBoxRadiusPx", Map("section", "Tunables", "type", "int"),
    "treeStableTicks", Map("section", "Tunables", "type", "int"),
    "treeClickCooldownMs", Map("section", "Tunables", "type", "int"),
    "treeWalkReclickTimeoutMs", Map("section", "Tunables", "type", "int"),
    "bankColor", Map("section", "Tunables", "type", "color"),
    "bankBlockW", Map("section", "Tunables", "type", "int"),
    "bankBlockH", Map("section", "Tunables", "type", "int"),
    "bankTolerance", Map("section", "Tunables", "type", "int"),
    "bankScanBottomUp", Map("section", "Tunables", "type", "int"),
    "bankImageAnchorX", Map("section", "Tunables", "type", "int"),
    "bankImageAnchorY", Map("section", "Tunables", "type", "int"),
    "bankImageW", Map("section", "Tunables", "type", "int"),
    "bankImageH", Map("section", "Tunables", "type", "int"),
    "bankImageSearchPaddingPx", Map("section", "Tunables", "type", "int"),
    "bankImageWaitTimeoutMs", Map("section", "Tunables", "type", "int"),
    "postDepositClickX", Map("section", "Tunables", "type", "int"),
    "postDepositClickY", Map("section", "Tunables", "type", "int"),
    "clickSettleMs", Map("section", "Tunables", "type", "int"),
    "clickSettleJitterPercent", Map("section", "Tunables", "type", "int"),
    "ctrlHoldSettleMs", Map("section", "Tunables", "type", "int"),
    "runMode", Map("section", "Settings", "type", "int"),
    "indicatorSlot", Map("section", "Settings", "type", "int")
)
timingSchema := Map(
    "clickSettle", Map("section", "Tunables", "baseMsKey", "clickSettleMs", "jitterPercentKey", "clickSettleJitterPercent"),
    "ctrlHoldSettle", Map("section", "Tunables", "baseMsKey", "ctrlHoldSettleMs", "jitterPercentKey", "clickSettleJitterPercent"),
    "bankImagePoll", Map("section", "Tunables", "baseMsKey", "bankImagePollMs"),
    "postDepositSettle", Map("section", "Tunables", "baseMsKey", "postDepositSettleMs")
)

iniPath := A_ScriptDir "\..\..\Config\auto-woodcutting.ini"
botConfig := Config(iniPath, schema, timingSchema)
botConfig.Load()

botLogger := Logger(A_ScriptDir "\..\..\logs\auto-woodcutting-v4-debug.log")
botHumanizer := Humanizer(false)
botClicker := Clicker(botHumanizer)
botFailsafe := FailSafe(botLogger)
botWaiter := Waiter((baseMs, jitterPercent) => botHumanizer.Jitter(baseMs, jitterPercent))
botWindowFocus := WindowFocus()
botOverlay := Overlay(8, 10, 10)

ctx := EngineContext(botConfig, botLogger, botClicker, botFailsafe, botWaiter, botWindowFocus, botOverlay)

; Inventory layout is a fixed property of this client window (not a
; game-state tunable), so it's a hardcoded constant - same values
; every other bot uses for this window.
inventoryLayout := Map("firstX", 2099, "firstY", 801, "cols", 4, "rows", 7, "slotW", 72, "slotH", 64, "gapX", 12, "gapY", 8)
ctx.inventory := Inventory(inventoryLayout)
fullGate := SlotGate(botConfig.Get("indicatorSlot"), botConfig.Get("colorTolerance"), ctx.inventory)
ctx.inventory.SetFullGate(fullGate)
ctx.inventory.SetEmptyGate(NotGate(fullGate))

; Deposit-open interface image anchor - confirms the deposit box is
; actually open before clicking "deposit all". Same deposit interface
; as Motherlode, so its calibrated image is reused directly.
bankImagePath := A_ScriptDir "\..\..\Images\deposit-motherlode.png"
bankImageRegion := Map(
    "x1", botConfig.Get("bankImageAnchorX") - botConfig.Get("bankImageSearchPaddingPx"),
    "y1", botConfig.Get("bankImageAnchorY") - botConfig.Get("bankImageSearchPaddingPx"),
    "x2", botConfig.Get("bankImageAnchorX") + botConfig.Get("bankImageW") + botConfig.Get("bankImageSearchPaddingPx"),
    "y2", botConfig.Get("bankImageAnchorY") + botConfig.Get("bankImageH") + botConfig.Get("bankImageSearchPaddingPx")
)
bankImageAnchor := ImageAnchor(bankImageRegion, bankImagePath, botConfig.Get("bankImageW"), botConfig.Get("bankImageH"))

; ChopWoodPhase built first (needed by DepositBankPhase's own
; nextCyclePhases, so ChopWoodPhase's TargetLock gets reset on every
; depositBank->chopWood handoff); its own nextCyclePhases array is
; back-filled with DepositBankPhase right after that's constructed.
chopWoodNextCyclePhases := []
botChopWoodPhase := ChopWoodPhase(
    botConfig.Get("treeColor"), botConfig.Get("colorTolerance"),
    botConfig.Get("treeBlockW"), botConfig.Get("treeBlockH"), botConfig.Get("treeScanBottomUp"),
    botConfig.Get("treeTrackBoxRadiusPx"), botConfig.Get("treeStableTicks"),
    botConfig.Get("targetLockMoveTolerancePx"), botConfig.Get("treeClickCooldownMs"),
    botConfig.Get("treeWalkReclickTimeoutMs"), chopWoodNextCyclePhases, botConfig.Get("runMode")
)

botDepositBankPhase := DepositBankPhase(
    botConfig.Get("bankColor"), botConfig.Get("bankTolerance"),
    botConfig.Get("bankBlockW"), botConfig.Get("bankBlockH"), botConfig.Get("bankScanBottomUp"),
    bankImageAnchor, botConfig.Get("bankImageWaitTimeoutMs"), "bankImagePoll",
    botConfig.Get("postDepositClickX"), botConfig.Get("postDepositClickY"), "postDepositSettle",
    [botChopWoodPhase], botConfig.Get("runMode")
)
chopWoodNextCyclePhases.Push(botDepositBankPhase)

botEngine := Engine(ctx, botConfig.Get("runnerTickMs"))
ctx.engine := botEngine
botEngine.AddPhase(botChopWoodPhase, botConfig.Get("phaseTimeoutChopWood"))
botEngine.AddPhase(botDepositBankPhase, botConfig.Get("phaseTimeoutBank"))

F5:: botEngine.Start("chopWood")
F6:: {
    botEngine.Stop("Stopped (F6)")
    botOverlay.Clear()
}
