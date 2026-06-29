# Prompt: Extending the v3 OSRS Gathering Automation Foundation

Paste this into a new AI session to onboard it to this v3 project.

---

I have an OSRS (Old School RuneScape) automation **v3 foundation** in AutoHotkey v2, in the folder `v3/`. Read `docs/DOCUMENTATION.md` first — it fully describes the architecture, every library primitive, config system, and design conventions. Don't start writing code until you've read it.

The v3 foundation has been fully built and validated:
- 14 shared lib files (all syntax-check clean)
- 1 end-to-end template script (`template-bot.ahk` for reference)
- Generalized primitives for slots, markers, walking, targeting
- Config database with named composite shapes
- Context object replacing per-function global boilerplate

**Your role:** Build individual bots (miner, fisher, smelter, smith, cooker, motherlode, fighter) **one at a time**, from scratch, using the v3 foundation as your toolkit. Each bot is a new script, NOT a port of v2's scripts — but it will be dramatically shorter and simpler because the v3 lib does the heavy lifting.

## Hard rules for v3 bots

1. **No raw `PixelGetColor`, `Click`, `MouseMove`, `PixelSearch`, `ImageSearch` in bot scripts.** Every one of those already has a wrapper in `lib/` (Colors.ahk, Images.ahk, Click.ahk). If the exact thing I need doesn't exist, add it to the right lib file, not inline in the script, so every future bot gets it too.

2. **Every phase function starts with `RequireOsrsWindowActive(ctx)`** and returns its own name to retry if it fails. This maintains the `ctx["paused"]` state properly.

3. **Call `ResetPhaseTimer(ctx["runner"])` after real progress.** Every v3 lib primitive that succeeds (`DoMarkerAction*`, `WalkToMarker`, `WaitForSlotChange`, `AcquireTarget`, `BankDepositAll`) calls this automatically. Only hand-rolled phases need to call it manually.

4. **Inventory/slot checks use `Slots.ahk`.** Calibrate any slot (1-28) with `CalibrateSlotSignature(slotIndex)`, check for changes with `WaitForSlotChange(ctx, sig, ...)` or `HasSlotChanged(sig)`. One primitive, any direction (empty→occupied, occupied→empty, item→different-item).

5. **Use `Marker.ahk` for click-confirm-press-wait sequences.** Instead of hand-assembling "find marker → click → wait for dialog → press key → wait for slot change", call `DoMarkerActionAndWaitForSlotChange(...)` once. Shorter, safer, consistent across all bots.

6. **Use `Walk.ahk` for walking with arrival detection.** Click a destination marker, wait for an arrival signal (a different color/image appearing, or the destination marker vanishing). Real signal-based waiting, not flat-second guesses.

7. **Targeting uses blob-centroid detection, not edge-pixel-plus-offset.** Call `AcquireTarget(ctx, targetRegion, ...)` — it finds the geometric center of a colored outline blob and clicks it directly. No offset parameter needed; the centroid is guaranteed inside the blob.

8. **Config lives in Db.ahk, not scattered globals.** Use named shapes: `DbGetMarker(config, "Marker:FurnaceMarker")`, `DbGetSlotSignature(config, "SlotSignature:InventoryCheck")`, `DbGetWithdrawPlan(config, "WithdrawPlan:Default")`. One section per logical thing.

9. **Calibration hotkeys use `Db.ahk` setters.** After capturing a coord/color/region/signature via hotkey, save it with `DbSetMarker(...)`, `DbSetSlotSignature(...)`, etc. Load them back in `LoadConfig()` with the corresponding `DbGet*` calls.

10. **One context object per script, all phases read from it.** `ctx := NewBotContext(configFile)` at startup. Every phase takes `(ctx, runner)` instead of declaring `global X, Y, Z`. Phases access tunables/markers/images/etc via `CtxTunable(ctx, key)`, `CtxMarker(ctx, name)`, etc.

11. **Validate once at startup.** Build one `ValidateSetup()` function with one `Require*` call per calibrated value, ending in `return ShowValidationErrors(v)`. This runs before `StartTaskRunner()` and reports ALL problems in one popup.

12. **Run vs walk is a `.ini` flag.** Load `ctx["runMode"] := DbGet(config, "Settings", "runMode", false, "bool")` once at startup. Pass it to `HumanClick(x, y, ..., ctx["runMode"])` for Ctrl-hold running.

13. **`confirmTicks` defaults to 3 (debounce-by-default).** Override it only if you have a specific reason to trust the first poll (e.g., an explicit dialog that either is or isn't there with no flicker risk). The default 3 filters one-frame glitches.

14. **Debug logging uses `LogLine(logFile, text)`.** Append timestamped lines to `ctx["logFile"]` for post-hoc diagnosis. Only if your bot benefits from it; logging is optional.

15. **Coordinates given as "WxH px, position x=,y=" are TOP-LEFT corners.** Use Grid.ahk's helpers or Grid-like conversions (halve width/height, add to x/y to get center). Never use corners directly as click targets.

## Standard structure for a new v3 bot

```ahk
#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\lib\[include all relevant libs]

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

global CONFIG := A_ScriptDir "\..\config\your-bot.ini"
global LOG_FILE := A_ScriptDir "\..\logs\your-bot-debug.log"
global ctx := NewBotContext(CONFIG)

LoadConfig()

; Calibration hotkeys (F1-F4, adjust per your needs)
F1:: CalibrateX()
F2:: CalibrateY()
F3:: CalibrateZ()
F4:: ...

; Bot lifecycle
F5:: StartBot()
F6:: StopAndLog(ctx["runner"], "Stopped (F6)")
F7:: ClearConfigAndReload()

; Phase functions
Phase1(runner) {
    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "phase1")
    ; ...
}

Phase2(runner) {
    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "phase2")
    ; ...
}

LoadConfig() {
    ; DbGet* calls populating ctx shapes from CONFIG
}

ValidateSetup() {
    v := NewValidator()
    ; Require* calls for every calibrated value
    return ShowValidationErrors(v)
}

StartBot() {
    if (!ValidateSetup())
        return
    ctx["runner"] := NewTaskRunner(150)
    AddPhase(ctx["runner"], "phase1", Phase1, 30000)
    AddPhase(ctx["runner"], "phase2", Phase2, 30000)
    StartTaskRunner(ctx["runner"], "phase1")
}
```

## Testing/safety practices

- **Syntax-check before running:** `& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut "path\to\your-script.ahk"`
  - Lib files (no hotkeys) should exit cleanly with no output.
  - Bot scripts (with hotkeys) will stay resident; that's normal. Launch via a PowerShell process, confirm it stays resident ~2s with no error output, then kill it.

- **Never kill an AutoHotkey process you didn't just launch yourself.** It might be the user's own live testing session. If unsure, ask.

- **Don't claim a bot "works" from a syntax check alone.** That only proves it loads. Say explicitly that in-game behavior is unverified unless the user has tested it live.

- **Test in-game before unattended runs.** Calibrate, run one manual cycle, verify it does what you expect. Then you can trust it for longer runs.

## Keeping docs current

If you add a new lib function, a new primitive, or establish a new convention, update `docs/DOCUMENTATION.md` to match. Keep this file (`PROMPT.md`) in sync if you establish a new hard rule the user should know about.

---

**v3 Foundation Onboarding — Built for clarity, robustness, and bot-to-bot consistency. Read DOCUMENTATION.md first!**
