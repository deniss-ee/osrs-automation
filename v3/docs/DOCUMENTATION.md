# OSRS Gathering Automation v3 — Foundation Architecture

This folder contains the **v3 foundation** — a cleaner, more generalized library layer and config system for OSRS bot scripts written in AutoHotkey v2. v3 was built from the ground up to:

1. Replace binary (last/second-to-last slot only) inventory checks with **arbitrary-slot (1-28), direction-agnostic change detection**
2. Unify fragmented withdraw-sequence shapes into one canonical form
3. Add real marker-based walking (click destination, wait for arrival signal) instead of flat-seconds guesses
4. Correct NPC targeting from nearest-edge-pixel-plus-guessed-offset to true **blob-centroid detection**
5. Replace heavy per-function `global X,Y,Z` boilerplate with one **context object**
6. Make config simpler via a unified `DbGet`/`DbSet` accessor + named composite shapes

**v2 stays untouched** as a working reference (folder structure, libs, scripts, docs remain at the root `lib/`, `scripts/`, `config/`, etc.). v3 is purely additive — a new `v3/` folder with its own `lib/`, `config/`, `images/`, `templates/`, and `docs/` subdirectories.

---

## Folder structure

```
v3/
├── lib/                shared function library (14 .ahk files, function-only, safe to #Include)
│   ├── Context.ahk     bot context object (replaces global boilerplate)
│   ├── Db.ahk          config database (replaces ConfigStore.ahk)
│   ├── Colors.ahk      pixel-color detection (redesigned: ctx-first, confirmTicks=3 default)
│   ├── Images.ahk      ImageSearch detection (ctx-first waits)
│   ├── Click.ahk       click primitive (ported unchanged)
│   ├── Slots.ahk       arbitrary-slot change detection (NEW)
│   ├── Marker.ahk      click-confirm-act sequence (NEW)
│   ├── Walk.ahk        marker-walk-with-arrival-wait (NEW)
│   ├── Targeting.ahk   NPC blob-centroid detection (NEW)
│   ├── Bank.ahk        deposit/withdraw operations (unified plan shape)
│   ├── Grid.ahk        UI coordinate presets (ported unchanged)
│   ├── TaskRunner.ahk  phase state machine (ported unchanged)
│   ├── Safety.ahk      window-focus + paused state (redesigned)
│   ├── Paths.ahk       path record/playback (guarded-only form)
│   ├── Validate.ahk    setup validation (+ 2 new checks)
│   ├── Log.ahk         debug logging (auto-creates parent log directory)
│   └── Tooltip.ahk     on-screen feedback (ported unchanged)
├── config/             per-bot .ini files (created at calibration; gitignored)
├── images/             reference PNGs for ImageSearch (empty initially; filled per-bot)
├── templates/
│   └── template-bot.ahk  end-to-end example (exercises all primitives once)
├── docs/
│   ├── DOCUMENTATION.md  (this file)
│   └── PROMPT.md        onboarding hard-rules doc
└── tools/
    └── db-inspect.ahk   optional: dumps .ini in human-readable form
```

No `scripts/` folder yet — real bots (miner, fisher, smelter, smith, cooker, motherlode, fighter) are built in a separate pass, one at a time, starting from `template-bot.ahk` as the reference skeleton.

---

## Context object (`Context.ahk`)

Replaces the per-function `global X,Y,Z` boilerplate that sprawled across v2. One `Map` every phase function receives:

```ahk
ctx := NewBotContext(configFile)
; Returns a Map with:
;   .config (str)
;   .tunables (Map: str -> any)
;   .elements, .markers, .images, .slotSignatures, .withdrawPlans, .targetRegions, .paths (all Maps)
;   .runner (TaskRunner object)
;   .logFile (str)
;   .runMode (bool)
;   .paused (bool)
```

Access via convenience functions: `CtxTunable(ctx, "key")`, `CtxMarker(ctx, "name")`, etc. — no boilerplate in phases.

---

## Config database (`Db.ahk`)

Stays `.ini`-based (human-editable, native AHK support, no new parser dependency). Simplification is in the **API surface**:

- **One generic accessor** (replaces 9 Save*/Load* pairs):
  ```ahk
  DbGet(configFile, section, key, default, type := "auto")
  DbSet(configFile, section, key, value, type := "auto")
  ```
  Types: `"auto"` (infer), `"int"`, `"num"`, `"str"`, `"bool"`, `"color"`

- **Named composite shapes** (multi-key/multi-row, kept as helpers):
  - `DbGetPoint/DbSetPoint` → `{x, y}`
  - `DbGetRegion/DbSetRegion` → `{x1, y1, x2, y2}`
  - `DbGetElement/DbSetElement` → `{x, y, w, h}` (UI region)
  - `DbGetMarker/DbSetMarker` → `{color, tolerance, x1, y1, x2, y2, clickOffsetX, clickOffsetY}`
  - `DbGetImage/DbSetImage` → `{file, w, h, options, x1, y1, x2, y2}`
  - `DbGetSlotSignature/DbSetSlotSignature` → `{slot, points: [{x, y, color}]}`
  - `DbGetWithdrawPlan/DbSetWithdrawPlan` → `[{slot, count}, ...]` (unified shape)
  - `DbGetTargetRegion/DbSetTargetRegion` → `{color, tolerance, x1, y1, x2, y2}`
  - `DbGetPath/DbSetPath` → `[{x, y, pause, button, running}, ...]`

Each logical thing (a marker, a UI element, an image, a slot signature) is one self-describing `.ini` section (e.g. `[Marker:FurnaceMarker]`, `[SlotSignature:InventoryCheck]`), not scattered loose globals.

Sentinels: `-1` = uncalibrated color, `0,0` = uncalibrated coord (carried forward from v2).

---

## Core lib modules

### `Colors.ahk` — pixel-color detection layer

**Changes from v2:**
- All wait functions take `ctx` as first parameter (for paused checks), not optional trailing `runningVarGetter`
- `confirmTicks` defaults to 3 (debounce-by-default), not 1
- Dropped deprecated `FindNearestPixelColor`; `FindNearestPixelColorSpiral` renamed `FindNearestColor`
- Dropped `IsSlotOccupied`, `IsAnyPointOccupied`, `WaitUntilOccupied`, `WaitUntilNotOccupied` (moved to `Slots.ahk`)
- Kept `FindShapeCentroid` (used by `Targeting.ahk`)

**Primitives:**
- `ColorClose(c1, c2, tol)` — per-channel RGB tolerance check
- `IsColorAt(x, y, color, tol)` — read one pixel + compare
- `WaitForPixelColor(ctx, x, y, expectedColor, tol, timeoutMs, confirmTicks := 3, pollMs := 100)`
- `WaitForPixelColorChange(ctx, x, y, awayFromColor, tol, timeoutMs, confirmTicks := 3, pollMs := 100)`
- `WaitForEitherPixelColor(ctx, x1, y1, color1, x2, y2, color2, tol, timeoutMs, pollMs := 100)`
- `WaitForPixelSearch(ctx, &foundX, &foundY, x1, y1, x2, y2, color, tol, timeoutMs, pollMs := 150)`
- `FindNearestColor(x1, y1, x2, y2, refX, refY, color, tol, &foundX, &foundY, maxDistance := 1000)` — true center-outward spiral
- `FindShapeCentroid(x1, y1, x2, y2, color, tol, &centerX, &centerY, sampleRate := 1)` — average position of all matching pixels
- `IsAnyOreColor(currentColor, baseColor, tol, useGreenFallback := false)` — tolerant ore match with optional green heuristic

### `Images.ahk` — ImageSearch detection layer

**Changes from v2:**
- Wait functions (`WaitUntilImageGone`, `WaitForImageCenter`, `WaitForImageNearButton`) take `ctx` first parameter
- `confirmTicks` defaults to 3

**Primitives:**
- `FindImageCenter(x1, y1, x2, y2, imageFile, imgW, imgH, &centerX, &centerY, options := "")` — finds image center (not upper-left)
- `IsImagePresent(x1, y1, x2, y2, imageFile, options := "")`
- `WaitUntilImageGone(ctx, x1, y1, x2, y2, imageFile, timeoutMs, confirmTicks := 3, options := "", pollMs := 200)`
- `WaitForImageCenter(ctx, x1, y1, x2, y2, imageFile, imgW, imgH, &centerX, &centerY, timeoutMs, options := "", pollMs := 200)`
- `WaitForImageNearButton(ctx, button, imageFile, imgW, imgH, &centerX, &centerY, timeoutMs, margin := 20, options := "", pollMs := 200)`
- `FindAnyImageCenter(x1, y1, x2, y2, images, imgW, imgH, &centerX, &centerY, &matchedImage, options := "")` — tries multiple images

### `Slots.ahk` (NEW) — arbitrary-slot change detection

**Replaces:** v2's `IsSlotOccupied` + `IsAnyPointOccupied` + `WaitUntilOccupied` + `WaitUntilNotOccupied` + the binary last/second-to-last slot flag.

**Key insight:** Calibrate any slot's baseline (whatever state was present when F-key was pressed), then detect ANY change from that baseline, direction-agnostic. Same code, different calibration = mining (empty→occupied), smelting full depletion (full→empty), item transformation (ore→bar, raw→cooked — same count, different item), withdrawing (empty→filled-with-specific-item).

**Smelting completion modes** (two patterns, choose by `smeltWaitMode` tunable):
- `"empty"` — use `WaitForSlotEmpty`: slot goes to the hardcoded empty-background color. For ores that are fully consumed (e.g. coal, iron at the right ratio).
- `"change"` — use `CalibrateSlotSignature` **before** pressing Space (captures ore pixels as baseline), then `WaitForSlotChange` after: detects when the item texture changes to the bar. Use this for gold ore → gold bar (1:1 ratio, slot never empties, just transforms).

**Primitives:**
- `CalibrateSlotSignature(slotIndex, offsets := "")` → `{slot, points: [{x, y, color}]}` for any slot 1-28
- `HasSlotChanged(sig, tol := 15)` — true if ANY point differs from baseline
- `IsSlotUnchanged(sig, tol := 15)` — inverse
- `WaitForSlotChange(ctx, sig, tol, timeoutMs, confirmTicks := 3, pollMs := 100)`
- `WaitForSlotUnchanged(ctx, sig, tol, timeoutMs, confirmTicks := 3, pollMs := 100)`
- `RecaptureSlotSignature(sig)` — re-calibrate to current state for chained checks

**Global hardcoded empty-slot support (no calibration required):**
- `INVENTORY_EMPTY_COLOR` is defined once in `Grid.ahk` from `v3/images/inv-empty.png`
- `GetEmptySlotSignature(slotIndex, offsets := "")`
- `IsSlotEmpty(slotIndex, tol := 15, offsets := "")`
- `IsSlotOccupied(slotIndex, tol := 15, offsets := "")`
- `WaitForSlotEmpty(ctx, slotIndex, tol, timeoutMs, confirmTicks := 3, pollMs := 100, offsets := "")`
- `WaitForSlotOccupied(ctx, slotIndex, tol, timeoutMs, confirmTicks := 3, pollMs := 100, offsets := "")`

### `Marker.ahk` (NEW) — generalized click-confirm-act sequence

**Replaces:** the 5-line hand-assembled sequence smelter/cooker/smith repeat (find marker → click → wait for dialog image → press key → wait for slot change).

**Primitives:**
- `DoMarkerAction(ctx, marker, markerTimeoutMs, confirm := "", confirmTimeoutMs := 0, actionKey := "", keySettleMs := 100)` → true if all steps succeeded
  - `marker`: `{color, tolerance, x1, y1, x2, y2, clickOffsetX, clickOffsetY}`
  - `confirm`: (optional) image or pixel spec (can be omitted)
  - `actionKey`: (optional) key to press (e.g. "Space")
- `DoMarkerActionAndWaitForSlotChange(ctx, marker, markerTimeoutMs, confirm, confirmTimeoutMs, actionKey, keySettleMs, sig, slotTol, slotTimeoutMs, slotConfirmTicks := 3)` — full cycle including the slot change wait

### `Walk.ahk` (NEW) — auto-walk with arrival detection

**Replaces:** flat-seconds sleeps (motherlode's `Sleep(10s)` guess) + recorded path playback with no arrival confirmation.

**Primitives:**
- `WalkToMarker(ctx, destMarker, markerTimeoutMs, arrival, arrivalTimeoutMs, confirmTicks := 3)` — click destination marker, then block until arrival signal confirms walk completed
  - `destMarker`: `{color, tolerance, x1, y1, x2, y2, clickOffsetX, clickOffsetY}`
  - `arrival`: one of four shapes:
    - `{mode: "appear", color, tolerance, x, y}` — wait for pixel to appear
    - `{mode: "appear", file, w, h, x1, y1, x2, y2, options}` — wait for image to appear
    - `{mode: "disappear", color, tolerance, x, y}` — wait for pixel to disappear (e.g. marker vanishing)
    - `{mode: "disappear", file, ...}` — wait for image to disappear

### `Targeting.ahk` (NEW) — NPC blob-centroid targeting

**Replaces:** v2's `auto-fighter.ahk` approach (find nearest outline pixel, click past it with guessed offset). v3 computes the true geometric center of the colored outline blob.

**Key difference:** The nearest-pixel search is used only as a **seed** to locate which blob is closest (when multiple targets exist). The actual click target is the **centroid** of pixels around that seed, which is guaranteed to be inside the blob regardless of its shape.

**Primitives:**
- `FindOutlineBlobCenter(x1, y1, x2, y2, color, tolerance, &targetX, &targetY, sampleRate := 2)` — centroid of all matching pixels in region
- `FindNearestOutlineBlobCenter(x1, y1, x2, y2, refX, refY, color, tolerance, &targetX, &targetY, blobRadius := 60, sampleRate := 2)` — nearest blob's centroid to reference point
- `AcquireTarget(ctx, targetRegion, refX, refY, blobRadius := 60, sampleRate := 2, clickCount := 1, clickDelayMs := 10)` → true if target found and clicked
  - `targetRegion`: `{color, tolerance, x1, y1, x2, y2}`
  - **No click offset parameter** — centroid is already inside the blob

### `Bank.ahk` — deposit/withdraw unified

**Changes from v2:**
- `BankDepositAll` now takes `ctx` (first param)
- New `BankWithdrawPlan(plan, interSettleMs, finalSettleMs)` unifies smelter's array + smith's two constants

**Primitives:**
- `BankDepositAll(ctx, depositImg, settleMs, failsafeMs, imgW := 72, imgH := 72, openTimeoutMs := 15000, searchMargin := 20, imgOptions := "*20")` — settles, waits for button image, clicks once, failsafe pause
- `BankWithdrawSlot(slotIndex, settleMs)` — click one slot (1-8), settle pause
- `BankWithdrawPlan(plan, interSettleMs, finalSettleMs)` — execute ordered `[{slot, count}, ...]` sequence with two-tier settlement

### `Paths.ahk` — recorded path playback

**Changes from v2:**
- Only the guarded form exists, renamed `PlayPath(ctx, steps, timeoutMs := 0)`
- No unguarded `PlayPath()` — the footgun is structurally absent

**Primitives:**
- `NewPathRecorder()` → `{active, name, lastTick, steps}`
- `StartRecording(recorder, pathName)`
- `StopRecording(recorder)` → steps array
- `RecordClickStep(recorder, x, y, button := "Left", runningFlag := 0)`
- `ApplyRunningDelayScale(delayMs, wasRunning, scaleFactor := 0.535)` — compress pause for running
- `PlayPath(ctx, steps, timeoutMs := 0)` — guarded playback only; aborts if ctx stops or timeout

### `Safety.ahk` — window-focus + paused state

**Changes from v2:**
- New `UpdatePausedState(ctx, winTitle)` — maintains explicit `ctx["paused"]` flag with sustained tooltip
- `RequireOsrsWindowActive(ctx, winTitle)` now ctx-aware and manages paused state
- Kept `IsCoordOnScreen`, `IsRegionValid`, `RequireOnScreen` unchanged

**Primitives:**
- `IsOsrsWindowActive(winTitle := "ahk_exe RuneLite.exe")`
- `UpdatePausedState(ctx, winTitle)` — sets `ctx["paused"]` + shows/hides sustained tooltip
- `RequireOsrsWindowActive(ctx, winTitle)` — call first in every phase
- `IsCoordOnScreen(x, y)`, `IsRegionValid(x1, y1, x2, y2)`, `RequireOnScreen(label, x, y)`

### `Grid.ahk`, `Click.ahk`, `TaskRunner.ahk`, `Validate.ahk`, `Log.ahk`, `Tooltip.ahk`

**Ported essentially as-is** from v2, with targeted v3 updates. `Validate.ahk` gains two new checks: `RequireSlotSignature` and `RequireTargetRegion`. `Log.ahk` now ensures the target log directory exists before appending, so scripts can safely log to `v3\logs\*.log` even when the directory is missing.

---

## Design conventions for v3 scripts

1. **No raw `PixelGetColor`, `Click`, `MouseMove`, `PixelSearch`, `ImageSearch` in scripts.** Always use the lib wrappers (`Colors.ahk`, `Images.ahk`, `Click.ahk`). If you need something new, add it to a lib file so all future scripts get it.

2. **Every phase function starts with `RequireOsrsWindowActive(ctx)`** and returns its own name to retry if it fails.

3. **Every phase that stays active for minutes while working correctly calls `ResetPhaseTimer(ctx["runner"])`** after real progress (successful click, completed action, state change confirmed). New v3 primitives (`DoMarkerAction*`, `WalkToMarker`, `WaitForSlotChange`, `AcquireTarget`) call this automatically.

4. **Calibrate via hotkeys, persist via `Db.ahk`, validate via `Validate.ahk`.** A script's `ValidateSetup()` is one `Require*` call per F-key (or per config value that needs checking), ending in `return ShowValidationErrors(v)`.

5. **Inventory/slot checks use `Slots.ahk`:** either calibrate any slot (1-28) with `CalibrateSlotSignature(slotIndex)` and check changes via `HasSlotChanged(sig)` / `WaitForSlotChange(ctx, sig, ...)`, or use the global hardcoded-empty helpers `IsSlotEmpty` / `WaitForSlotEmpty` when a bot only needs emptiness checks.

6. **Any "did state change" check should debounce with `confirmTicks`** (default 3 in v3). This filters out one-frame glitches (character sprite, camera settling).

7. **Coordinates are always top-left corner + size**, converted to true center internally by `Grid.ahk` helpers. Do not use them directly as click centers.

8. **Run vs walk is a `.ini` flag** (`[Settings] runMode`), read once at startup into `ctx["runMode"]`.

9. **Walking uses markers whenever possible** (click destination marker, wait for arrival signal via `WalkToMarker`), falling back to recorded paths only where no marker is available.

10. **`ENABLE_HUMANIZATION` defaults to false** in `Click.ahk` (exact calibrated pixel, exact delays). Humanization is hard-capped at ±2px / ±100ms even when enabled.

---

## Structural smells designed away in v3

**Smell-1: Global boilerplate.** Solved by `Context.ahk` — every phase reads through `ctx`, not 15 `global` lines.

**Smell-2: Unguarded playback.** Solved by keeping only `PlayPath(ctx, ...)` — the old footgun `PlayPath()` (no abort support) doesn't exist in v3.

**Smell-3: Dead deprecated code.** `FindNearestPixelColor` was marked DEPRECATED in v2 but still shipped; v3 drops it entirely.

**Smell-4: Busy-poll paused state.** Solved by explicit `ctx["paused"]` flag with sustained tooltip instead of silent retry.

**Smell-5: Binary slot index, occupied/empty only.** Solved by `Slots.ahk` — any slot 1-28, any direction-agnostic change detection.

**Smell-6: Debounce opt-in, not default.** Solved by raising `confirmTicks` default to 3 across all v3 wait functions.

**Smell-7: Hand-assembled marker sequences.** Solved by `Marker.ahk` — one call replaces 5 hand-coded lines, auto-calls `ResetPhaseTimer`.

**Smell-8: Walking without arrival signals.** Solved by `Walk.ahk` — marker-click-then-wait for real signal, replaces guessing.

**Smell-9: Edge-pixel targeting with guessed offset.** Solved by `Targeting.ahk` — true blob centroid, no offset guess needed.

---

## Config sentinels and validation

- `-1` = uncalibrated color (v2 convention, kept in v3)
- `0,0` = uncalibrated coord (v2 convention, kept in v3)
- Empty arrays = uncalibrated list (e.g., an unrecorded path or unrecorded walk sequence)

All `DbGet*` functions tolerate missing keys via defaults, so a partial or hand-edited `.ini` still loads.

---

## Next steps: Building a real v3 script

1. Copy `v3/templates/template-bot.ahk` and rename for your bot (e.g. `auto-smelter-v3.ahk`)
2. Adjust the phases to match your bot's cycle (gather → bank, mine → deposit → return, etc.)
3. Use `Slots.ahk`, `Marker.ahk`, `Walk.ahk`, `Bank.ahk` primitives instead of hand-wiring sequences
4. Add calibration hotkeys following the template pattern
5. Load all config shapes via `DbGet*` in `LoadConfig()`
6. Validate via `Validate.ahk` calls in `ValidateSetup()`
7. Test in-game; adjust tunables via `.ini` or hotkey-based calibration

**Syntax-check before running:** `& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut "path\to\your-script.ahk"`

---

## Verification notes

- All v3 lib files syntax-check clean (no output = successful load)
- `template-bot.ahk` syntax-checks and registers all hotkeys correctly
- In-game behavior (actual bot cycles, marker detection, bank depositing, NPC targeting) requires live testing with OSRS — not proven until a real bot runs
- Config `.ini` files are created at calibration time; start with an empty `config/your-bot.ini` and let the script populate it

---

**v3 Foundation Architecture © 2026 | Built on v2 legacy patterns, generalized and optimized for clarity and robustness.**
