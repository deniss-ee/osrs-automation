; ============================================================
; agility.ahk
; v4 entry point + Agility phase.
;
; Loops through a course of obstacles (count/size/position/color per
; step defined in Config/auto-agility.ini's [Step:N] sections - see
; [Settings] stepCount): find the current step's colored highlight
; block, click its center, settle, advance to the next step (wrapping
; back to 1), repeat forever. Every value that varies per course - step
; count, each step's calibration, the Mark of Grace image size, the
; pickup-confirmation box, and the fall-recovery block - lives in the
; .ini, so adapting this bot to a different course is a config change,
; not a code change.
;
; Each step's highlight color should be unique across the whole course
; (see [Step:N] comments in the .ini) - this is what makes Mark of
; Grace recovery simple: after a loot detour moves the player off a
; step's calibrated position, the SAME step can be re-found within the
; dynamic search region (see below) by its own color alone, with no
; ambiguity against other steps.
;
; Mark of Grace: every tick, before ever touching the current
; step's obstacle coordinates, search the whole screen for
; Images/mog-item.png (once per step, latched via
; checkedMarkForStep). If found, click it, then poll a small fixed
; pixel box (the item-count area) every graceConfirmPollMs up to
; gracePickupTimeoutMs for a change - confirms an item actually
; landed, not just that a click happened. Whether that confirms or
; times out, the next obstacle search switches to "dynamic" mode
; (a bounded region around screen-center, fixed-size block, still
; keyed on the step's own color) since the player likely moved to
; reach the mark - bounded rather than whole-screen since a mark
; detour is only ever a short walk, and a full-screen PixelSearch-based
; scan is expensive.
;
; Fall recovery: only checked while stuck waiting for the marker of the
; step right after [FallRecovery] afterStep (falling off the course is
; known to happen after that specific step). If that step's own
; highlight isn't found, search for the configured fall-recovery block
; (the "back on solid ground" marker) - if found, click it, reset to
; step 1, and let the normal per-tick search pick up from there.
; [FallRecovery] enabled=0 disables this check entirely.
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
#Include ..\..\Detection\StaticAnchor.ahk
#Include ..\..\Interfaces\SlotSignature.ahk
#Include ..\..\Actions\Humanizer.ahk
#Include ..\..\Actions\Click.ahk
#Include ..\..\Config\Config.ahk
#Include ..\..\Diagnostics\Logger.ahk
#Include ..\..\Diagnostics\WindowFocus.ahk
#Include ..\..\Diagnostics\Overlay.ahk

; ============================================================
; Obstacle calibration - read from Config/auto-agility.ini's [Step:N]
; sections ([Settings] stepCount controls how many). No search-box
; padding: the search region is exactly each block's own footprint,
; nothing added. See LoadSteps below.
; ============================================================

; Reads [Step:1]..[Step:stepCount] into the STEPS array shape the phase
; expects. pollKey points at that step's own timing key (stepSearchPoll1..N,
; defined in timingSchema below, backed by that same [Step:N] section's
; own stepSearchPollNMs key) - different obstacles take different
; real-world time to traverse, so each needs its own tunable poll
; interval instead of one shared value.
LoadSteps(iniPath, stepCount) {
    steps := []
    loop stepCount {
        n := A_Index
        section := "Step:" n
        steps.Push(Map(
            "w", Integer(IniRead(iniPath, section, "w")),
            "h", Integer(IniRead(iniPath, section, "h")),
            "x", Integer(IniRead(iniPath, section, "x")),
            "y", Integer(IniRead(iniPath, section, "y")),
            "color", Integer(IniRead(iniPath, section, "color")),
            "pollKey", "stepSearchPoll" n
        ))
    }
    return steps
}

; ============================================================
; AgilityPhase - per step: check once for a Mark of Grace, then
; find the current step's highlight block (fixed calibrated box,
; or whole-screen if a loot detour may have moved the player),
; click its center, settle, advance.
; ============================================================
class AgilityPhase extends Phase {
    __New(steps, colorTolerance, stepSearchDelayKey, dynamicSearchBlockSizePx, dynamicRegion,
          mogAnchor, graceClickOffsetY, slotSignature, gracePreDelayKey,
          graceConfirmPollKey, gracePickupTimeoutMs, gracePickedUpDelayKey,
          fallRecoveryDelayKey, fallRecoveryBlock := "", runMode := false) {
        super.__New("agility")
        this._steps := steps
        this._colorTolerance := colorTolerance
        this._stepSearchDelayKey := stepSearchDelayKey
        this._dynamicSearchBlockSizePx := dynamicSearchBlockSizePx
        this._dynamicRegion := dynamicRegion
        this._mogAnchor := mogAnchor
        this._graceClickOffsetY := graceClickOffsetY
        this._slotSignature := slotSignature
        this._gracePreDelayKey := gracePreDelayKey
        this._graceConfirmPollKey := graceConfirmPollKey
        this._gracePickupTimeoutMs := gracePickupTimeoutMs
        this._gracePickedUpDelayKey := gracePickedUpDelayKey
        this._fallRecoveryDelayKey := fallRecoveryDelayKey
        this._fallRecoveryBlock := fallRecoveryBlock
        this._runMode := runMode
    }

    ResetForNewCycle() {
        ; currentStep persists across the whole run - no per-cycle reset.
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "agility"

        currentStep := ctx.Get("currentStep", 1)
        step := this._steps[currentStep]

        ; --- Obstacle search: fixed calibrated box, or a bounded region
        ; around screen-center at a fixed generic block size if a loot
        ; detour may have moved us. Bounded (not whole-screen) because a
        ; full-screen PixelSearch-based scan is expensive and a mark
        ; detour only ever moves the player a short walk, never far
        ; enough to land outside this region. ---
        dynamicActive := ctx.Get("dynamicSearchActive", false)
        if (dynamicActive) {
            x1 := this._dynamicRegion["x1"]
            y1 := this._dynamicRegion["y1"]
            x2 := this._dynamicRegion["x2"]
            y2 := this._dynamicRegion["y2"]
            reqW := this._dynamicSearchBlockSizePx
            reqH := this._dynamicSearchBlockSizePx
        } else {
            x1 := step["x"] - step["w"] // 2
            y1 := step["y"] - step["h"] // 2
            x2 := step["x"] + step["w"] // 2
            y2 := step["y"] + step["h"] // 2
            reqW := step["w"]
            reqH := step["h"]
        }

        found := ColorSearch.FindFilledBlock(x1, y1, x2, y2,
            step["color"], this._colorTolerance, reqW, reqH, &cx, &cy)

        if (!found) {
            ; Fall recovery: falling off the course after a specific step
            ; (fallRecoveryBlock["afterStep"]) lands the player somewhere
            ; the NEXT step's marker never appears. Only checked while
            ; stuck on that specific next step, since that's the one step
            ; falling is known to affect for this course.
            if (this._fallRecoveryBlock != "" && currentStep = this._fallRecoveryBlock["afterStep"] + 1) {
                fb := this._fallRecoveryBlock
                fx1 := fb["x"] - fb["w"] // 2
                fy1 := fb["y"] - fb["h"] // 2
                fx2 := fb["x"] + fb["w"] // 2
                fy2 := fb["y"] + fb["h"] // 2
                if (ColorSearch.FindFilledBlock(fx1, fy1, fx2, fy2,
                    fb["color"], this._colorTolerance, fb["w"], fb["h"], &fcx, &fcy)) {
                    ctx.Log("AgilityPhase: Detected fall-recovery block at [" fcx ", " fcy "]. Waiting before clicking.")
                    ctx.waiter.After(ctx.timing, this._fallRecoveryDelayKey)
                    ctx.Log("AgilityPhase: Clicking fall-recovery block, resetting to step 1.")
                    ctx.clicker.ClickSettled(ctx, fcx, fcy, this._runMode)
                    ctx.failsafe.ResetPhaseTimer(ctx)
                    ctx.Set("currentStep", 1)
                    ctx.Set("checkedMarkForStep", false)
                    ctx.Set("dynamicSearchActive", false)
                    return "agility"
                }
            }

            ctx.Log("AgilityPhase: Waiting for step " currentStep (dynamicActive ? " (dynamic, [" x1 "," y1 "]-[" x2 "," y2 "])" : " (" step["w"] "x" step["h"] " at " step["x"] "," step["y"] ")"))
            ctx.waiter.After(ctx.timing, step["pollKey"])
            return "agility"
        }

        ; --- Mark of Grace check (once per step, only once the step's own
        ; highlight has actually been found - i.e. we've arrived/settled
        ; and are about to click it, not mid-walk toward it) ---
        if (!ctx.Get("checkedMarkForStep", false)) {
            ctx.waiter.After(ctx.timing, this._gracePreDelayKey)

            loop {
                ctx.Log("AgilityPhase: Searching for Mark of Grace...")
                if (!this._mogAnchor.Find(&mx, &my)) {
                    ctx.Log("AgilityPhase: No Mark of Grace found.")
                    break
                }

                clickY := my + this._graceClickOffsetY
                ctx.Log("AgilityPhase: Found Mark of Grace at [" mx ", " my "]. Clicking at [" mx ", " clickY "].")
                sig := this._slotSignature.Snapshot()
                ctx.clicker.ClickSettled(ctx, mx, clickY, this._runMode)

                deadline := A_TickCount + this._gracePickupTimeoutMs
                changed := false
                loop {
                    if (this._slotSignature.HasChanged(sig)) {
                        changed := true
                        break
                    }
                    if (A_TickCount >= deadline)
                        break
                    ctx.waiter.After(ctx.timing, this._graceConfirmPollKey)
                }

                ; Either way we moved to reach it (or attempted to) - the
                ; current step's fixed calibrated box may no longer be
                ; valid. Re-search for the step's highlight fresh next
                ; tick rather than trusting the (cx,cy) found before the
                ; detour.
                ctx.Set("dynamicSearchActive", true)
                ctx.failsafe.ResetPhaseTimer(ctx)

                if (changed) {
                    ctx.Log("AgilityPhase: Mark of Grace pickup confirmed.")
                    ; Brief settle after a CONFIRMED pickup only - the
                    ; inventory update just landed, give the client a beat
                    ; before searching again. The timed-out case below gets
                    ; no delay: nothing changed, so there's nothing to
                    ; settle from.
                    ctx.waiter.After(ctx.timing, this._gracePickedUpDelayKey)
                    ; Loop again - another mark may be visible.
                    continue
                }

                ; Timed out: the mark is still on screen (unreachable/out
                ; of range for this step) or the click missed - re-finding
                ; it next tick would just click the exact same spot again
                ; forever. Give up on marks for this step and move on.
                ctx.Log("AgilityPhase: Mark of Grace pickup timed out - giving up for this step.")
                break
            }

            ctx.Set("checkedMarkForStep", true)

            ; A loot detour happened - (cx,cy) was found before we
            ; potentially moved, and dynamicSearchActive is now on for a
            ; reason. Re-tick so the obstacle search runs fresh (whole
            ; screen at the dynamic block size) instead of clicking a
            ; stale point.
            if (ctx.Get("dynamicSearchActive", false))
                return "agility"
        }

        ctx.Log("AgilityPhase: Found step " currentStep " at [" cx ", " cy "]. Clicking.")
        ctx.clicker.ClickSettled(ctx, cx, cy, this._runMode)
        ctx.failsafe.ResetPhaseTimer(ctx)

        nextStep := currentStep + 1
        if (nextStep > this._steps.Length)
            nextStep := 1
        ctx.Set("currentStep", nextStep)
        ctx.Set("checkedMarkForStep", false)
        ctx.Set("dynamicSearchActive", false)

        ; Settle before the next tick starts searching for the new step -
        ; don't hammer the search on the same tick as the click.
        ctx.waiter.After(ctx.timing, this._stepSearchDelayKey)

        return "agility"
    }
}

; ============================================================
; Wiring
; ============================================================

iniPath := A_ScriptDir "\..\..\Config\auto-agility.ini"

; stepCount drives how many stepSearchPollNMs keys/[Step:N] sections exist -
; read directly (ahead of Config's own schema-validated Load()) since
; Config's schema is static and can't express "N keys, N from the ini
; itself".
stepCount := Integer(IniRead(iniPath, "Settings", "stepCount"))

schema := Map(
    "runnerTickMs", Map("section", "Tunables", "type", "int"),
    "phaseTimeoutAgility", Map("section", "Tunables", "type", "int"),
    "colorTolerance", Map("section", "Tunables", "type", "int"),
    "stepSearchDelayMs", Map("section", "Tunables", "type", "int"),
    "dynamicSearchBlockSizePx", Map("section", "MarkOfGrace", "type", "int"),
    "mogShadeTolerance", Map("section", "MarkOfGrace", "type", "int"),
    "graceClickOffsetY", Map("section", "MarkOfGrace", "type", "int"),
    "gracePrePickupDelayMs", Map("section", "MarkOfGrace", "type", "int"),
    "gracePickupTimeoutMs", Map("section", "MarkOfGrace", "type", "int"),
    "gracePickedUpDelayMs", Map("section", "MarkOfGrace", "type", "int"),
    "fallRecoveryDelayMs", Map("section", "FallRecovery", "type", "int"),
    "graceConfirmPollMs", Map("section", "MarkOfGrace", "type", "int"),
    "clickSettleMs", Map("section", "ClickExecution", "type", "int"),
    "clickSettleJitterPercent", Map("section", "ClickExecution", "type", "int"),
    "ctrlHoldSettleMs", Map("section", "ClickExecution", "type", "int"),
    "runMode", Map("section", "Settings", "type", "int"),
    "stepCount", Map("section", "Settings", "type", "int")
)
timingSchema := Map(
    "clickSettle", Map("section", "ClickExecution", "baseMsKey", "clickSettleMs", "jitterPercentKey", "clickSettleJitterPercent"),
    "ctrlHoldSettle", Map("section", "ClickExecution", "baseMsKey", "ctrlHoldSettleMs", "jitterPercentKey", "clickSettleJitterPercent"),
    "stepSearchDelay", Map("section", "Tunables", "baseMsKey", "stepSearchDelayMs"),
    "gracePreDelay", Map("section", "MarkOfGrace", "baseMsKey", "gracePrePickupDelayMs"),
    "graceConfirmPoll", Map("section", "MarkOfGrace", "baseMsKey", "graceConfirmPollMs"),
    "gracePickedUpDelay", Map("section", "MarkOfGrace", "baseMsKey", "gracePickedUpDelayMs"),
    "fallRecoveryDelay", Map("section", "FallRecovery", "baseMsKey", "fallRecoveryDelayMs")
)
loop stepCount {
    n := A_Index
    timingSchema["stepSearchPoll" n] := Map("section", "Step:" n, "baseMsKey", "stepSearchPoll" n "Ms")
}

botConfig := Config(iniPath, schema, timingSchema)
botConfig.Load()

botLogger := Logger(A_ScriptDir "\..\..\logs\auto-agility-v4-debug.log")
botHumanizer := Humanizer(false)
botClicker := Clicker(botHumanizer)
botFailsafe := FailSafe(botLogger)
botWaiter := Waiter((baseMs, jitterPercent) => botHumanizer.Jitter(baseMs, jitterPercent))
botWindowFocus := WindowFocus()
botOverlay := Overlay(4, 10, 10)

ctx := EngineContext(botConfig, botLogger, botClicker, botFailsafe, botWaiter, botWindowFocus, botOverlay)

STEPS := LoadSteps(iniPath, stepCount)

; Dynamic obstacle re-acquisition region (used after a Mark of Grace
; detour, see AgilityPhase.Run) - bounded around screen-center rather
; than the whole screen, since a mark detour is a short walk, never far
; enough to move the highlight outside this region, and a full-screen
; PixelSearch-based scan is expensive.
dynamicRegionCenterX := Integer(IniRead(iniPath, "MarkOfGrace", "dynamicRegionCenterX"))
dynamicRegionCenterY := Integer(IniRead(iniPath, "MarkOfGrace", "dynamicRegionCenterY"))
dynamicRegionWidth := Integer(IniRead(iniPath, "MarkOfGrace", "dynamicRegionWidth"))
dynamicRegionHeight := Integer(IniRead(iniPath, "MarkOfGrace", "dynamicRegionHeight"))
dynamicRegion := Map(
    "x1", dynamicRegionCenterX - dynamicRegionWidth // 2,
    "y1", dynamicRegionCenterY - dynamicRegionHeight // 2,
    "x2", dynamicRegionCenterX + dynamicRegionWidth // 2,
    "y2", dynamicRegionCenterY + dynamicRegionHeight // 2
)

; Mark of Grace detection - whole-screen image search, single reference
; image. mog-item.png is captured against a #00FF00 matte, so *TransARGB
; is required or ImageSearch tries to literally match those green pixels
; against the real (non-green) game background and never finds it.
; Shade-variation tolerance (ImageSearch's "*N" option, 0-255) is ALSO
; needed - a live game capture is rarely pixel-identical to the reference
; PNG (anti-aliasing, lighting, animation) even ignoring the matte.
mogImageW := Integer(IniRead(iniPath, "MarkOfGrace", "imageW"))
mogImageH := Integer(IniRead(iniPath, "MarkOfGrace", "imageH"))
mogRegion := Map("x1", 0, "y1", 0, "x2", A_ScreenWidth, "y2", A_ScreenHeight)
mogImagePath := A_ScriptDir "\..\..\Images\mog-item.png"
mogOptions := "*" botConfig.Get("mogShadeTolerance") " *Trans0x00FF00"
mogAnchor := ImageAnchor(mogRegion, mogImagePath, mogImageW, mogImageH, mogOptions)

; Pickup confirmation - a small fixed box (the item-count area) that
; visibly changes once a Mark of Grace lands in the inventory.
botSlotSignature := SlotSignature(
    Integer(IniRead(iniPath, "MarkOfGrace", "slotSignatureX")),
    Integer(IniRead(iniPath, "MarkOfGrace", "slotSignatureY")),
    Integer(IniRead(iniPath, "MarkOfGrace", "slotSignatureW")),
    Integer(IniRead(iniPath, "MarkOfGrace", "slotSignatureH"))
)

; Fall recovery - only checked while stuck waiting for the marker of
; (afterStep + 1) (falling off the course is known to happen after a
; specific step). Clicking this returns to solid ground; the phase then
; resets to step 1 and lets the normal per-tick search pick it up from
; there. "" disables the check entirely (enabled=0, or no known fall
; point for this course).
fallRecoveryBlock := ""
if (Integer(IniRead(iniPath, "FallRecovery", "enabled")) = 1) {
    fallRecoveryBlock := Map(
        "afterStep", Integer(IniRead(iniPath, "FallRecovery", "afterStep")),
        "w", Integer(IniRead(iniPath, "FallRecovery", "w")),
        "h", Integer(IniRead(iniPath, "FallRecovery", "h")),
        "x", Integer(IniRead(iniPath, "FallRecovery", "x")),
        "y", Integer(IniRead(iniPath, "FallRecovery", "y")),
        "color", Integer(IniRead(iniPath, "FallRecovery", "color"))
    )
}

botAgilityPhase := AgilityPhase(
    STEPS, botConfig.Get("colorTolerance"),
    "stepSearchDelay", botConfig.Get("dynamicSearchBlockSizePx"), dynamicRegion,
    mogAnchor, botConfig.Get("graceClickOffsetY"), botSlotSignature,
    "gracePreDelay", "graceConfirmPoll", botConfig.Get("gracePickupTimeoutMs"), "gracePickedUpDelay",
    "fallRecoveryDelay", fallRecoveryBlock, botConfig.Get("runMode")
)

botEngine := Engine(ctx, botConfig.Get("runnerTickMs"))
ctx.engine := botEngine
botEngine.AddPhase(botAgilityPhase, botConfig.Get("phaseTimeoutAgility"))

F5:: botEngine.Start("agility")
F6:: {
    botEngine.Stop("Stopped (F6)")
    botOverlay.Clear()
}
; Test-only: start directly on the step right after fallRecoveryBlock's
; afterStep, to test fall-recovery in isolation without running the whole
; course first (assumes the player is already standing at the
; fall-recovery coordinates).
F9:: {
    if (fallRecoveryBlock = "") {
        ctx.Log("F9: Fall recovery is disabled in .ini - nothing to test.")
        return
    }
    ctx.Set("currentStep", fallRecoveryBlock["afterStep"] + 1)
    ctx.Set("checkedMarkForStep", false)
    ctx.Set("dynamicSearchActive", false)
    botEngine.Start("agility")
}
