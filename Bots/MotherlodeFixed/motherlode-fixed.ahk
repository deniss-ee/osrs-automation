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
; VeinChecker - shared "is this fixed-position vein active" check,
; used by both MinePhase and ReturnToMinePhase (previously duplicated
; verbatim in each).
;
; Pads the search box beyond the required block size (searchPaddingPx)
; - a box exactly the block's own size leaves FindFilledBlock's
; VerifyBlock zero room to spare, so even a few pixels of calibration
; drift makes a genuinely active vein read as inactive. Every other
; fixed-point search in this bot (DepositBankPhase's
; depositSearchPaddingPx) already pads beyond its block size.
;
; Guards against the padded boxes of two different veins overlapping
; (which would let one vein's color falsely match inside the other's
; search box) by clamping the padded box so it never crosses the
; midpoint between the two veins - this makes the padding safe by
; construction instead of relying on the two vein colors happening to
; differ by more than the color tolerance.
; ============================================================
class VeinChecker {
    __New(blockW, blockH, tolerance, searchPaddingPx, otherVeinX := "", otherVeinY := "") {
        this._blockW := blockW
        this._blockH := blockH
        this._tolerance := tolerance
        this._searchPaddingPx := searchPaddingPx
        this._otherVeinX := otherVeinX
        this._otherVeinY := otherVeinY
    }

    IsActive(vein) {
        hw := this._blockW // 2 + this._searchPaddingPx
        hh := this._blockH // 2 + this._searchPaddingPx
        x1 := vein["x"] - hw
        y1 := vein["y"] - hh
        x2 := vein["x"] + hw
        y2 := vein["y"] + hh

        if (this._otherVeinX != "") {
            midX := (vein["x"] + this._otherVeinX) / 2
            midY := (vein["y"] + this._otherVeinY) / 2
            x1 := vein["x"] < this._otherVeinX ? Max(x1, midX) : Min(x1, midX)
            x2 := vein["x"] < this._otherVeinX ? Min(x2, midX) : Max(x2, midX)
            y1 := vein["y"] < this._otherVeinY ? Max(y1, midY) : Min(y1, midY)
            y2 := vein["y"] < this._otherVeinY ? Min(y2, midY) : Max(y2, midY)
        }

        return ColorSearch.FindFilledBlock(
            Min(x1, x2), Min(y1, y2), Max(x1, x2), Max(y1, y2),
            vein["color"], this._tolerance, this._blockW, this._blockH, &cx, &cy)
    }
}

; ============================================================
; MissDebounce - "has this been missing for N consecutive checks"
; counter. A plain, purpose-built replacement for borrowing TargetLock
; (a position/stability-debounce class for a MOVING target) to get
; this one narrow behavior for a FIXED point that never moves - using
; TargetLock here worked, but only by disabling most of what it does
; (stableTicksRequired=0, moveTolerancePx=0, dummy coordinates), which
; is a fragile implicit dependency on TargetLock's internals never
; changing to consult those now-inert fields.
; ============================================================
class MissDebounce {
    __New(missingTicksToUnlock) {
        this._missingTicksToUnlock := missingTicksToUnlock
        this._missingTicks := 0
    }

    ; True once `found` has been false for missingTicksToUnlock
    ; consecutive Observe() calls.
    Observe(found) {
        this._missingTicks := found ? 0 : this._missingTicks + 1
    }

    IsLost() => this._missingTicks >= this._missingTicksToUnlock

    Reset() {
        this._missingTicks := 0
    }
}

; ============================================================
; MinePhase - two fixed-position veins, no walking/searching.
;
; While a vein is marked active (activeVein scratch key set), only
; that vein's fixed point is checked - still active means the
; ongoing mining action continues on its own, no re-click needed.
; Once it's been MISSING for missingTicksToUnlock consecutive ticks
; (a MissDebounce, tolerating single-frame detection flicker from
; animation/particle effects rather than reacting to the very first
; miss), activeVein clears and BOTH points are checked again on the
; same tick (a switch shouldn't cost an idle poll first).
;
; The failsafe timer is reset only on genuine progress - a click, or
; a fresh hit after having been missing at all - never on every
; "still active, nothing changed" tick. Core/FailSafe.ahk's own
; contract is "call after real progress, NOT on every tick"; resetting
; it on every steady-state tick would let phaseTimeoutMine never fire
; even if the vein got stuck active for a reason unrelated to actual
; mining (a stray overlay/graphical glitch permanently painting that
; pixel, for instance) - the 180s ceiling needs to mean something.
;
; "Never abandon a still-active vein just because the other lit up"
; falls out naturally from only ever checking the active vein's own
; point while one is locked in - the other vein's state is never
; even read until the current one is confirmed depleted.
; ============================================================
class MinePhase extends Phase {
    __New(veinA, veinB, veinCheckerA, veinCheckerB, missingTicksToUnlock, minePollKey, runMode := false) {
        super.__New("mine")
        this._veinA := veinA   ; {x, y, color}
        this._veinB := veinB
        this._veinCheckerA := veinCheckerA
        this._veinCheckerB := veinCheckerB
        this._minePollKey := minePollKey
        this._runMode := runMode
        this._debounce := MissDebounce(missingTicksToUnlock)
        this._wasMissing := false
    }

    ResetForNewCycle() {
        this._debounce.Reset()
        this._wasMissing := false
    }

    _VeinAndChecker(label) {
        return label = "A" ? [this._veinA, this._veinCheckerA] : [this._veinB, this._veinCheckerB]
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "mine"

        if (ctx.inventory.IsFull()) {
            ctx.Log("MinePhase: Inventory full, transitioning to depositBank")
            ctx.Set("activeVein", "")
            this._debounce.Reset()
            this._wasMissing := false
            ctx.Set("depositPreDelayApplied", false)
            ctx.Set("returnClicked", false)
            ctx.Set("returnWaitStartedAt", 0)
            return "depositBank"
        }

        active := ctx.Get("activeVein", "")

        if (active != "") {
            pair := this._VeinAndChecker(active)
            found := pair[2].IsActive(pair[1])
            this._debounce.Observe(found)

            if (!this._debounce.IsLost()) {
                if (found && this._wasMissing) {
                    ; Genuine recovery after a tolerated miss - real
                    ; progress, worth extending the failsafe budget.
                    ctx.failsafe.ResetPhaseTimer(ctx)
                }
                this._wasMissing := !found
                return "mine"
            }

            ctx.Log("MinePhase: Vein " active " depleted. Checking for another.")
            ctx.Set("activeVein", "")
            this._debounce.Reset()
            this._wasMissing := false
            active := ""
        }

        ; No vein currently locked in - check A, then B (A preferred
        ; when both are simultaneously active, same as before).
        if (this._veinCheckerA.IsActive(this._veinA)) {
            ctx.clicker.ClickSettled(ctx, this._veinA["x"], this._veinA["y"], this._runMode)
            ctx.Set("activeVein", "A")
            this._debounce.Reset()
            this._wasMissing := false
            ctx.Log("MinePhase: Clicked vein A at [" this._veinA["x"] ", " this._veinA["y"] "]")
            ctx.failsafe.ResetPhaseTimer(ctx)
            return "mine"
        }
        if (this._veinCheckerB.IsActive(this._veinB)) {
            ctx.clicker.ClickSettled(ctx, this._veinB["x"], this._veinB["y"], this._runMode)
            ctx.Set("activeVein", "B")
            this._debounce.Reset()
            this._wasMissing := false
            ctx.Log("MinePhase: Clicked vein B at [" this._veinB["x"] ", " this._veinB["y"] "]")
            ctx.failsafe.ResetPhaseTimer(ctx)
            return "mine"
        }

        ; Neither vein active yet - throttle below the raw engine tick
        ; rate instead of hammering PixelSearch every tick.
        ctx.waiter.After(ctx.timing, this._minePollKey)
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
    __New(color, tolerance, reqW, reqH, markerX, markerY, searchPaddingPx, depositAnchor, imageWaitTimeoutMs, imagePollKey, preClickDelayKey, markerPollKey, runMode := false) {
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
        this._markerPollKey := markerPollKey
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
            ctx.waiter.After(ctx.timing, this._markerPollKey)
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
    __New(clickX, clickY, veinA, veinB, veinCheckerA, veinCheckerB, veinPollKey, waitTimeoutMs, nextCyclePhases, runMode := false) {
        super.__New("returnToMine")
        this._clickX := clickX
        this._clickY := clickY
        this._veinA := veinA
        this._veinB := veinB
        this._veinCheckerA := veinCheckerA
        this._veinCheckerB := veinCheckerB
        this._veinPollKey := veinPollKey
        this._waitTimeoutMs := waitTimeoutMs
        this._nextCyclePhases := nextCyclePhases
        this._runMode := runMode
    }

    ResetForNewCycle() {
        ; returnClicked/returnWaitStartedAt are reset by this phase's own
        ; completion below, alongside every other phase's per-cycle state.
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

        if (this._veinCheckerA.IsActive(this._veinA) || this._veinCheckerB.IsActive(this._veinB)) {
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
    "minePollMs", Map("section", "Tunables", "type", "int"),
    "depositMarkerPollMs", Map("section", "Tunables", "type", "int"),
    "veinTolerance", Map("section", "Tunables", "type", "int"),
    "veinAX", Map("section", "Tunables", "type", "int"),
    "veinAY", Map("section", "Tunables", "type", "int"),
    "veinAColor", Map("section", "Tunables", "type", "color"),
    "veinBX", Map("section", "Tunables", "type", "int"),
    "veinBY", Map("section", "Tunables", "type", "int"),
    "veinBColor", Map("section", "Tunables", "type", "color"),
    "veinBlockW", Map("section", "Tunables", "type", "int"),
    "veinBlockH", Map("section", "Tunables", "type", "int"),
    "veinSearchPaddingPx", Map("section", "Tunables", "type", "int"),
    "veinMissingTicksToUnlock", Map("section", "Tunables", "type", "int"),
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
    "returnVeinPoll", Map("section", "Tunables", "baseMsKey", "returnVeinPollMs"),
    "minePoll", Map("section", "Tunables", "baseMsKey", "minePollMs"),
    "depositMarkerPoll", Map("section", "Tunables", "baseMsKey", "depositMarkerPollMs")
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
; Each checker knows the OTHER vein's position, so its padded search box
; is clamped at the midpoint between the two veins - the two boxes can
; never overlap regardless of how the two vein colors happen to be
; calibrated (previously, only the color-tolerance gap prevented a
; false cross-vein match in the overlap region).
botVeinCheckerA := VeinChecker(botConfig.Get("veinBlockW"), botConfig.Get("veinBlockH"), botConfig.Get("veinTolerance"), botConfig.Get("veinSearchPaddingPx"), botConfig.Get("veinBX"), botConfig.Get("veinBY"))
botVeinCheckerB := VeinChecker(botConfig.Get("veinBlockW"), botConfig.Get("veinBlockH"), botConfig.Get("veinTolerance"), botConfig.Get("veinSearchPaddingPx"), botConfig.Get("veinAX"), botConfig.Get("veinAY"))

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
    "depositPreClickDelay", "depositMarkerPoll", botConfig.Get("runMode")
)

nextCyclePhases := [botDepositBankPhase]

botReturnToMinePhase := ReturnToMinePhase(
    botConfig.Get("returnClickX"), botConfig.Get("returnClickY"),
    veinA, veinB, botVeinCheckerA, botVeinCheckerB,
    "returnVeinPoll", botConfig.Get("returnWaitTimeoutMs"), nextCyclePhases, botConfig.Get("runMode")
)
nextCyclePhases.Push(botReturnToMinePhase)

botMinePhase := MinePhase(
    veinA, veinB, botVeinCheckerA, botVeinCheckerB, botConfig.Get("veinMissingTicksToUnlock"),
    "minePoll", botConfig.Get("runMode")
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
