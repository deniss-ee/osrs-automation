# OSRS Gathering Automation — Project Documentation

This folder contains AutoHotkey v2 (AHK2) scripts that automate OSRS gathering/processing/combat
(mining, fishing, smelting, banking, NPC fighting) by reading pixel colors/images and sending
clicks/keystrokes. It started as three standalone scripts written one at a time with no shared
code. They were analyzed, and a shared function library (`lib\`) was built from the reusable
parts, fixing several real bugs along the way. Every current script (`auto-fisher.ahk`,
`auto-smelter.ahk`, `auto-miner.ahk`, `auto-smith.ahk`, `auto-motherlode.ahk`, `auto-fighter.ahk`)
is built entirely from that library.

## Folder structure

```
auto gathering\
├── scripts\                             CURRENT real scripts, all built from lib\
│   ├── auto-fisher.ahk                  fishing
│   ├── auto-smelter.ahk                 smelting
│   ├── auto-miner.ahk                   mining
│   ├── auto-smith.ahk                   smithing
│   ├── auto-motherlode.ahk              Motherlode Mine
│   └── auto-fighter.ahk                 NPC combat
├── legacy\                              legacy scripts, untouched, reference only
│   └── motherlode-miner.ahk / .ini
├── tools\                               throwaway diagnostics, kept for reference
│   └── test-imagesearch.ahk
├── lib\                                 shared function library (AHK2 #Include files)
│   ├── Colors.ahk
│   ├── Click.ahk
│   ├── Images.ahk
│   ├── Safety.ahk
│   ├── Paths.ahk
│   ├── Bank.ahk
│   ├── Grid.ahk
│   ├── TaskRunner.ahk
│   ├── ConfigStore.ahk
│   ├── Validate.ahk
│   ├── Log.ahk
│   └── Tooltip.ahk
├── images\                              ImageSearch reference images (anch.png, deposit.png,
│                                         full/semifull/empty/semiempty/none/seminone.png)
├── config\                              auto-created .ini files (one or more per real script)
├── logs\                                debug logs (auto-fisher-debug.log, auto-smith-debug.log)
└── docs\
    ├── DOCUMENTATION.md                 this file
    └── PROMPT.md                        paste-able prompt for a future AI session
```

`lib\*.ahk` files contain **only function definitions** (no hotkeys, no top-level executable
code besides a few `global` constant defaults) so they're safe to `#Include` from anywhere. All
real scripts live in `scripts\` and `#Include ..\lib\X.ahk` (one level up, since they're now a
folder deeper than `lib\`). AHK2 resolves `#Include` relative to the **including file's own
directory**, and the same file is never included twice even if multiple files in the chain
include it (so `lib` files can `#Include` their own dependencies without causing duplicate
definitions when a script includes both directly). The same `..\` rule applies to every other
`A_ScriptDir`-relative path in a script — `CONFIG`, `LOG_FILE`, and any image path all need the
`..\` prefix to reach `config\`/`logs\`/`images\` from inside `scripts\` (or `tools\`/`legacy\`).

## Legacy scripts (do not maintain, keep as reference only)

`motherlode-miner.ahk`/`.ini` live in `legacy\`, intentionally left untouched.
`miner-3.ahk`/`.ini`, `smelter-1.ahk`/`.ini`, and
`miner-2-member.ini` (an orphan config with no matching script) used to live here too but have
since been relocated to a sibling `..\backup\` folder outside this project — they're not
deleted, just out of the way. All of these still work but have known structural issues that
motivated the library (see "Bugs found and fixed" below). Don't copy patterns from them into new
scripts — learn the conventions from `lib\` and from `scripts\auto-miner.ahk` /
`scripts\auto-smelter.ahk` instead. `auto-smith.ahk` (smithing) is the newest script, built the
same way; it cycles withdraw-bars → walk-to-anvil → Space → wait-empty → bank, and withdraws two
bank slots per trip.

`auto-miner.ahk` was itself promoted out of a `templates\single-ore-template.ahk` location
earlier in this project's life — despite the old name suggesting a teaching example, it was
already a real, actively-used mining script before the rename; the `templates\` folder no longer
exists.

---

## The shared library (`lib\`)

### `Colors.ahk` — pixel-color reading and comparison
No dependencies.

- `ColorClose(c1, c2, tol)` — tolerant per-channel RGB compare.
- `IsColorAt(x, y, color, tol)` — one-line `PixelGetColor`+`ColorClose` wrapper. The hard rule
  (`PROMPT.md`) is that no script calls `PixelGetColor` directly outside a one-time calibration
  hotkey — this is what `auto-miner.ahk`'s `MinePhase` uses to check an ore spot's current color
  against its calibrated "ready" color instead of inlining the pair itself.
- `WaitForPixelColor(x, y, expectedColor, tol, timeoutMs, confirmTicks:=1, pollMs:=100)` — poll
  until a pixel matches, for `confirmTicks` consecutive polls in a row, with a timeout. Returns
  bool. Same confirm-ticks debounce as `WaitForPixelColorChange` below, for the same reason.
- `WaitForPixelColorChange(x, y, awayFromColor, tol, timeoutMs, confirmTicks:=1, pollMs:=100)` —
  poll until a pixel **stops** matching, for `confirmTicks` consecutive polls in a row, with a
  timeout. The `confirmTicks` debounce exists because a single transient blip (character sprite
  or camera settling for a moment) can flicker one pixel and look exactly like "this rock just
  depleted" when it hasn't — raising this above 1 filters that out.
- `WaitForEitherPixelColor(x1,y1,color1, x2,y2,color2, tol, timeoutMs, pollMs:=100)` — race two
  coordinates, returns 1, 2, or 0 (timeout).
- `WaitForPixelSearch(&foundX, &foundY, x1,y1,x2,y2, color, tol, timeoutMs, pollMs:=150)` —
  bounded retry around `PixelSearch`.
- `FindNearestPixelColor(x1,y1,x2,y2, refX,refY, color, tol, &foundX,&foundY, stepPx:=20)` —
  finds the pixel APPROXIMATELY closest to `(refX,refY)` matching `color`, by searching a box
  centered on the reference point that grows by `stepPx` each pass (clipped to the rectangle)
  until `PixelSearch` finds a match or the box covers the whole rectangle. Not a true
  nearest-pixel scan (PixelSearch returns its own first match within the current box, not
  necessarily the closest point in it) but accurate to within one `stepPx` — used by
  `auto-fighter.ahk` to find the NPC combat-outline pixel closest to the character, since an
  outline is a ring with no single fixed point to search for.
- `IsSlotOccupied(x, y, emptyColor, tol:=15)` — true if the pixel does NOT match a calibrated
  empty-background color. The core idea: calibrate ONE empty-background reference, not a
  different "expected item color" per item — works for any item forever.
- `IsAnyPointOccupied(points, tol:=15)` — like `IsSlotOccupied` but checks a **list** of
  `{x, y, color}` points and returns true if ANY of them is occupied. Guards against a single
  sampled pixel landing on a "hole" in a specific item's icon shape.
- `WaitUntilOccupied(points, tol, timeoutMs, confirmTicks:=1, pollMs:=100)` /
  `WaitUntilNotOccupied(points, tol, timeoutMs, confirmTicks:=1, pollMs:=100)` — poll
  `IsAnyPointOccupied` until it becomes true / false, with the same confirm-ticks debounce.
  `WaitUntilNotOccupied` is what the smelter uses to detect "ore is gone from the last slot".
- `IsAnyOreColor(currentColor, baseColor, tol, useGreenFallback:=false)` — tolerant match with
  an optional green-dominant fallback (ported from motherlode-miner's vein-color heuristic).

### `Click.ahk` — the one click primitive
No dependencies. Defines `global ENABLE_HUMANIZATION := false`, `global MAX_CLICK_OFFSET_PX := 2`,
`global MAX_DELAY_JITTER_MS := 100`.

- `RandomOffset(maxX, maxY, &dx, &dy)` — random offset within `±maxX/2, ±maxY/2`, but never more
  than `±MAX_CLICK_OFFSET_PX` in either direction regardless of how big a box a call site passes
  in; always `0,0` while `ENABLE_HUMANIZATION` is false.
- `JitterDelay(baseMs, jitterPercent:=15)` — `baseMs` ± a random percentage, capped at
  `±MAX_DELAY_JITTER_MS` regardless of how large `baseMs` is, floored at 30ms; returns `baseMs`
  unchanged while `ENABLE_HUMANIZATION` is false.
- `HumanClick(centerX, centerY, width:=0, height:=0, holdCtrl:=false, button:="Left")` — THE
  click primitive every script uses. Picks a random point inside the `width x height` box
  (default 0×0 = exact pixel), jitters the post-move pause, optionally Ctrl-holds for running.
  Every "named region" in the library (bank slot, inventory slot, deposit button) is a
  `{x, y, w, h}` map so the standard call shape is always
  `HumanClick(thing["x"], thing["y"], thing["w"], thing["h"])`.

`ENABLE_HUMANIZATION` is a single global switch — set `false` in a script (after the
`#Include`s) to make every click/delay exact, e.g. while testing. No other code changes needed.
The `MAX_CLICK_OFFSET_PX`/`MAX_DELAY_JITTER_MS` hard caps exist so that humanization always stays
subtle no matter what box size or base delay a particular call site happens to pass — without
them, e.g. a 72px-wide bank slot click could land up to ±36px off-center, and jitter on an
800ms+ delay could swing by hundreds of ms.

### `Images.ahk` — ImageSearch-based detection
No dependencies. Parallel to `Colors.ahk`'s pixel-color layer, for graphical icons that don't
render as one reliable solid color (a fishing spot's ripple icon, a bank's Deposit All button).

- `FindImageCenter(x1,y1,x2,y2, imageFile, imgW,imgH, &centerX,&centerY, options:="")` — searches
  the region for `imageFile` and writes the CENTER of the match (ImageSearch itself only gives
  the upper-left corner). `imgW`/`imgH` must match the actual pixel size of the image file — AHK
  has no built-in way to query that at runtime. `options` passes straight through to
  `ImageSearch`, e.g. `"*Trans0x00FF00 *20"` to ignore a solid background color with some shade
  tolerance.
- `IsImagePresent(x1,y1,x2,y2, imageFile, options:="")` — plain presence check when you don't
  need the position back.
- `WaitUntilImageGone(x1,y1,x2,y2, imageFile, timeoutMs, confirmTicks:=1, options:="", pollMs:=200)`
  — polls until the image reads absent for `confirmTicks` consecutive polls, or times out. Same
  confirm-ticks debounce as `Colors.ahk`, same reason (a single missed frame shouldn't read as
  "really gone").
- `WaitForImageCenter(x1,y1,x2,y2, imageFile, imgW,imgH, &centerX,&centerY, timeoutMs, options:="", pollMs:=200)`
  — the complement: polls `FindImageCenter` until it finds a match or times out.
- `WaitForImageNearButton(button, imageFile, imgW,imgH, &centerX,&centerY, timeoutMs, margin:=20, options:="", pollMs:=200)`
  — same as `WaitForImageCenter`, but the search region is derived from a known UI element's
  `{x,y,w,h}` map (e.g. `GetDepositAllButton()`) padded by `margin` pixels, instead of a wide-area
  search. This is how every real script now waits for the bank to visibly open — by polling for
  the Deposit All button image near its known position — instead of guessing how long the walk +
  bank-open animation takes with a flat `Sleep`.
- `FindAnyImageCenter(x1,y1,x2,y2, images, imgW,imgH, &centerX,&centerY, &matchedImage, options:="")`
  — tries each image in the `images` array (in order) against the same region/size/options,
  returning the first match's center plus which image matched (via `&matchedImage`). For a state
  represented by more than one reference image — e.g. `auto-motherlode.ahk`'s mining-spot overlay,
  where a semi-transparent icon's actual on-screen shade drifts depending on what's behind it, so
  two PNGs (one direct color, one blended) bracket the same logical state — this lets a caller
  search for "any of these" as one logical match instead of repeating `FindImageCenter` calls
  inline.

### `Safety.ahk` — window focus + bounds checks
Depends on `Tooltip.ahk`.

- `IsOsrsWindowActive(winTitle:="ahk_exe RuneLite.exe")` / `RequireOsrsWindowActive(winTitle:=...)`
  — is the game window focused; the `Require*` version shows a tooltip and returns false instead
  of silently continuing. **Call this as the first line of every phase function.**
- `IsCoordOnScreen(x, y)` / `IsRegionValid(x1,y1,x2,y2)` — bounds + corner-ordering checks.
- `RequireOnScreen(label, x, y)` — named popup wrapper for setup validation.

### `Paths.ahk` — record/playback engine
Depends on `Click.ahk`. Defines `global MIN_RECORDED_DELAY := 50` and
`global INITIAL_CLICK_DELAY := 0`.

A path is an `Array` of step `Map`s: `{x, y, pause, button:="Left", running:=0}`.
**`pause` is the wait AFTER that step's click**, before the next step (or before the path is
done, for the last step). There's no separate "tail delay" — the last step's own `pause`
covers it. The wait before the very FIRST click of any path is the separate global
`INITIAL_CLICK_DELAY` (currently `0`), not something stored per-path.

- `RoundDelay(ms)` — rounds to nearest 50ms, 50ms floor.
- `NewPathRecorder()` — fresh `{active, name, lastTick, steps}` bundle, one per path.
- `StartRecording(recorder, pathName)` / `StopRecording(recorder)` — start/stop; stop computes
  the last step's `pause` from elapsed time and returns the finished `steps` array.
- `RecordClickStep(recorder, x, y, button:="Left", runningFlag:=0)` — call from your
  `~LButton`/`~RButton` hotkey handler while `recorder["active"]` is true. Sets the **previous**
  step's `pause` from elapsed time (this step's own `pause` is set later).
- `ApplyRunningDelayScale(delayMs, wasRunning, scaleFactor:=0.535)` — optional: compresses a
  pause to ~53.5% if `wasRunning` (OSRS run vs walk speed).
- `PlayPath(steps, jitter:=true, scaleRunDelay:=true)` — simple playback, no abort support.
- `PlayPathWithGuard(steps, runningVarGetter, timeoutMs:=0)` — playback that aborts (returns
  false) if `runningVarGetter()` becomes false or `timeoutMs` is exceeded. This is what scripts
  actually call.

### `Bank.ahk` — shared bank deposit/withdraw operations
Depends on `Grid.ahk`, `Images.ahk`, `Click.ahk`. The two bank actions every script shares,
extracted into one place so banking behaves identically across all four scripts instead of being
copy-pasted (and drifting) per script. Only the per-script hand-tuned delays are parameters; the
deposit-image parameters are identical everywhere and default.

- `BankDepositAll(depositImg, settleMs, failsafeMs, imgW:=72, imgH:=72, openTimeoutMs:=15000,
  searchMargin:=20, imgOptions:="*20")` — settle, then wait until the Deposit-All button image is
  actually visible near `GetDepositAllButton()`'s position (not a flat sleep), click it once, then
  a fail-safe pause. Returns `true` once deposited, `false` if the bank never visibly opened within
  `openTimeoutMs` (caller decides how to react — every script stops with "Bank never opened").
- `BankWithdrawSlot(slotIndex, settleMs)` — one left-click ("withdraw all" with this user's bank
  settings) on `GetBankSlots()[slotIndex]`, then a settle pause. **The settle matters**: checking
  inventory occupancy too soon after a withdrawal reads stale (the display hasn't updated yet) —
  pass a `settleMs` long enough for it to catch up (≈800ms before an immediate re-check; the miner
  uses 300ms because it walks away first).

### `Grid.ahk` — coordinate presets for this user's client layout
No dependencies. **Convention: every coordinate given to these functions is a TOP-LEFT corner +
size, not a center** (matches how the user describes UI elements: "72x64px... position
x=...,y=..."). The functions convert to true centers internally.

- `BuildGrid(firstX, firstY, lastX, lastY, cols, rows)` — generic linear-interpolation grid,
  row-major order (index 1 = top-left). Works on whatever anchor point you give it (corner or
  center) — don't mix the two within one call.
- `GetInventorySlots(firstX:=2099, firstY:=801, lastX:=2351, lastY:=1233)` — standard 4×7=28
  slot backpack, 72×64px each. Defaults are this user's measured top-left corners of slot 1 and
  slot 28; converted to true centers (slot 1 center `(2135,833)`, slot 28 center `(2387,1265)`).
- `GetBankSlots(baseX:=625, y:=203, step:=96, count:=8)` — flat list of 8 visible bank slots,
  72×64px, fixed y, x stepping by 96. Deliberately NOT a generic multi-row grid (the bank
  scrolls instead of showing more rows). Defaults give centers `661,757,853,949,1045,1141,
  1237,1333 @ y=235`.
- `GetDepositAllButton(x:=1363, y:=999, w:=72, h:=72)` — the bank's "Deposit all" button as a
  named clickable region. Default center derived from measured top-left `(1327,963)`.
- `GetDefaultSlotOffsets()` — `[[0,0],[-14,-12],[14,-12],[0,12]]`, a sane 4-point spread (dead
  center + 3 inset toward corners) for sampling inside one 72×64 slot.
- `GetSlotSamplePoints(slot, offsets)` — turns relative `[dx,dy]` offsets into absolute
  `{x,y}` points for a given slot.

### `TaskRunner.ahk` — named-phase state machine
Depends on `Tooltip.ahk`. This is the control-flow backbone every real script uses. It covers
BOTH shapes the legacy scripts used by hand: smelter-1's explicit phases and miner-3/
motherlode's reactive loop (which is really a 1-2 phase machine that never got named as one).

A phase is a function `(runner) => nextPhaseName`. Returning the **same** name means "stay in
this phase, tick again next interval" — this is exactly how the old reactive loops behaved.

- `NewTaskRunner(intervalMs:=150)` — runner state bundle. Builds and stores ONE bound closure
  (`runner["tickFn"]`) for the timer callback — **`SetTimer` needs the same function reference
  to start and stop a timer**, so this closure is created once and reused, never recreated.
- `AddPhase(runner, name, phaseFn, timeoutMs:=0)` — registers a phase. `timeoutMs` auto-stops
  the runner if stuck in that phase too long (0 = unlimited). **Important**: this timeout is
  measured from when the phase name was last entered, and does NOT reset just because the phase
  function returns its own name again — see `ResetPhaseTimer` below.
- `GoToPhase(runner, name)` — sugar, literally just returns `name`.
- `ResetPhaseTimer(runner)` — call this from inside a phase function after making real progress
  (e.g. right after a successful click, or after concluding a tracked target is genuinely gone)
  so the phase's `timeoutMs` means "no progress for this long" rather than "total time spent in
  this phase". **Forgetting this is a real bug class**: without it, a phase that's supposed to
  stay active for minutes while working correctly (e.g. "mine", "smelt", "fish") will eventually
  self-stop thinking it's stuck, even while it's working fine — and this includes the moment a
  phase function concludes "the thing I was tracking just left", not only the initial click.
- `StartTaskRunner(runner, startPhase)` / `StopTaskRunner(runner, reason:="Stopped")` —
  start/stop the timer-driven loop.
- `TickTaskRunner(runner)` — the timer callback. Busy-guard (prevents overlapping ticks),
  timeout check, `try/finally` around the phase call (so an exception mid-phase can't
  permanently wedge the busy flag).

### `ConfigStore.ahk` — generic INI persistence
No dependencies. Has no idea what an "ore" or "bank" is — only section/key names chosen by the
caller. All read functions tolerate missing keys via defaults (a hand-edited or partial INI
still loads).

- `SaveCoord`/`LoadCoord(configFile, section, key, ...)` — `key_x`/`key_y` pair.
- `SaveFlag`/`LoadFlag(configFile, section, key, default:=false)` — plain on/off setting (e.g.
  `runMode`). Stored as `1`/`0`.
- `SaveColor`/`LoadColor(configFile, section, key, defaultColor:=-1)` — single color; `-1` is
  this codebase's "not calibrated" sentinel.
- `SaveColorPointList`/`LoadColorPointList(configFile, section, points)` — an ordered list of
  `{x, y, color}` Maps. Used for both the ore-spot list (mining) AND the inventory reference
  points (mining + smelting + fishing) — same persistence code, different section names. Order
  is preserved on load.
- `SaveRegion`/`LoadRegion(configFile, section, ...)` — a 4-corner rectangle.
- `SavePath`/`LoadPath(configFile, section, steps)` — the canonical path format (see
  `Paths.ahk`). Writes/reads `count`, then `step{i}_x/y/pause/button/running` per step.

### `Validate.ahk` — setup-validation accumulator
Depends on `Safety.ahk`. Lets a script check every calibration value it needs and report ALL
problems in one popup, instead of stopping at the first missing F-key.

- `NewValidator()` — `{errors: []}` accumulator.
- `RequireColor`/`RequireCoord`/`RequireRegion`/`RequirePath(validator, label, ...)` — append a
  labeled error if unset (or, for coords/regions, off-screen — usually means stale calibration
  from a different monitor setup).
- `RequireNonEmpty(validator, label, list)` — generic "this list needs ≥1 entry" check, for
  things that aren't a path (e.g. the ore-spot list).
- `RequireFile(validator, label, path)` — appends a labeled error if `path` doesn't exist on
  disk. Used for the `*_IMG` globals (`anch.png`, `deposit.png`) so a missing/renamed image file
  fails clearly at startup instead of confusingly deep inside a phase at runtime.
- `HasErrors(validator)` / `ShowValidationErrors(validator, title:="Setup incomplete")` — joins
  all errors into one `MsgBox`; designed to be the final line of a script's `ValidateSetup()`.

### `Log.ahk` — minimal append-only debug logging
No dependencies.

- `LogLine(logFile, text)` — appends one timestamped line (`HH:mm:ss text`) to `logFile`. Useful
  when a tooltip might not actually be visible (e.g. the game running in a mode that draws over
  it) or when you need a record of an entire run, not just a 1-2 second flash of text. Currently
  only used by `auto-fisher.ahk` (`logs\auto-fisher-debug.log`) — `auto-smelter.ahk` and
  `auto-miner.ahk` don't include this file and have no logging.

### `Tooltip.ahk` — on-screen feedback
No dependencies.

- `ShowTip(text, x:="", y:="")` / `HideTip()` — defaults to top-right of screen.
- `ShowTipFor(text, durationMs, x:="", y:="")` — `ShowTip` + auto-hide in one call. Use this one
  almost everywhere.

---

## Design conventions (follow these for any new/edited script)

1. **No raw `PixelGetColor`/`Click`/`MouseMove`/`PixelSearch`/`ImageSearch` in a script.** If you
   need one, it belongs in `lib\` — extend an existing file or add a new one, so the next script
   gets it for free too.
2. **Every phase function starts with `RequireOsrsWindowActive()`** and returns its own name to
   retry if it fails.
3. **Every phase that can legitimately stay active a long time while working correctly calls
   `ResetPhaseTimer(taskRunner)` after making real progress** (a click, a completed path,
   concluding a tracked target is genuinely gone). The `AddPhase` timeout is a "stuck" detector,
   not a "max duration" cap.
4. **Calibrate via hotkeys, persist via `ConfigStore.ahk`, validate via `Validate.ahk`.** A
   script's `ValidateSetup()` should be one `RequireX` call per F-key (plus one `RequireFile`
   call per `*_IMG` global the script uses), ending in `return ShowValidationErrors(v)`.
5. **Inventory/slot occupancy is always multi-point**, never a single pixel. Calibrate via
   `GetSlotSamplePoints(slot, GetDefaultSlotOffsets())`, sample each point's color while the
   slot is genuinely empty, persist via `SaveColorPointList`, check via `IsAnyPointOccupied` /
   `WaitUntilOccupied` / `WaitUntilNotOccupied`.
6. **Any "wait for a rock/slot/spot to change state after I acted on it" check should debounce
   with `confirmTicks`** (a small number is typical) rather than trusting the first different-
   looking poll.
7. **Coordinates given as "WxH px, position x=,y="** are top-left corners — convert via
   `Grid.ahk`'s helpers, don't use them directly as click/sample centers.
8. **Run/walk is a plain `.ini` flag (`[Settings] runMode`), not a hotkey, not stamina-orb color
   reading.** Per-recorded-step `running` flags (in the path format) capture whatever `runMode`
   was at recording time.
9. **`ENABLE_HUMANIZATION`** defaults to `false` in `Click.ahk` (exact calibrated pixel, exact
   delays); even when enabled it's hard-capped at `±MAX_CLICK_OFFSET_PX` px / `±MAX_DELAY_JITTER_MS`
   ms. Every real script also restates `:= false` near the top (after the `#Include`s) so it's
   explicit per script — flip to `true` if you ever want the subtle randomized offset/jitter back.
10. **Waiting for the bank to visibly open uses image detection, not a flat guess.** Every real
    script's `BankPhase` does: a small settle delay (`BANK_OPEN_SETTLE_MS`) → poll for the
    Deposit All button image near its known position (`WaitForImageNearButton`, bounded by
    `BANK_OPEN_TIMEOUT_MS`) → click it → a small fail-safe delay (`BANK_OPEN_FAILSAFE_DELAY_MS`).
    Both delays apply every time, even if detection succeeds instantly — they're a safety margin,
    not a substitute for the detection itself. The exact delay values differ slightly between
    scripts (hand-tuned per script from live testing) — that's intentional, not drift.

### AHK v2 gotchas specific to this codebase

- **A function must explicitly `global X, Y` declare every module-level variable it touches**,
  read or write — AHK2 otherwise treats an assignment as creating a new local variable that
  shadows the real global (reads of a never-assigned-in-that-function variable do fall back to
  global automatically, but this codebase declares explicitly everywhere for clarity/safety,
  matching the legacy scripts' own habit).
- **`SetTimer(fn, period)` and `SetTimer(fn, 0)` need the EXACT SAME function reference** to
  start and stop a timer — a freshly-created closure (e.g. `() => Foo()`) is a NEW object every
  time it's evaluated, so it must be created once and stored, not recreated at each call site
  (see `TaskRunner.ahk`'s `runner["tickFn"]`).
- **`#Include` paths resolve relative to the including file's own directory**, and the same
  absolute file is never included twice even via different chains — so `lib\*.ahk` files can
  safely `#Include` their own dependencies. Moving a script to a different folder changes what
  `A_ScriptDir` evaluates to in that file, so every `A_ScriptDir`-based path string needs
  updating too, not just the `#Include` lines.
- **`ImageSearch` returns the match's top-left corner, not its center.** `imgW`/`imgH` must be
  hardcoded to match the actual image file's pixel dimensions (AHK2 has no runtime way to query
  an arbitrary file's size) — `Images.ahk`'s `FindImageCenter` does the corner-to-center
  conversion for you.
- Bracket access `obj["key"]` only works on `Map`; plain `{}` object literals use dot access
  (`obj.key`) only.

---

## Current real scripts

### `auto-fisher.ahk` — fishing bot
Lives in `scripts\`, built entirely from the library. Detects the fishing spot by IMAGE
(`anch.png` via `ImageSearch`), not a single pixel color, since the spot's ripple icon isn't one
flat color. Expected starting state: standing at the fishing spot with a net already in
inventory slot 1 and the rest empty.

- **Hotkeys**: F1/F2 = mark the two opposite corners of the calibrated fishing-area search
  region. F3 = calibrate inventory-full reference points (4 points on the last slot, inventory
  must be empty except the net). F4 = record the walk-to-fishing-spot path. F5/F6 = start/stop.
  F7 = clear config.
- **Cycle**: `FishPhase` searches the calibrated area for the spot image and clicks it once,
  then tracks that exact spot with a CONTINUOUSLY RE-CENTERING small search box — every poll
  re-searches a small box around wherever the spot was last found and updates that position to
  the new result, so the box slides along with however much the camera drifts while the
  character walks. This solves a real bug (see history below): a one-time "anchor and track a
  fixed box" approach goes stale almost immediately because the camera keeps panning for the
  ENTIRE duration of a walk, not just briefly after the click. Only many consecutive misses near
  the last known position conclude the spot actually left (moved or depleted) rather than just
  having drifted further than expected between polls. Exits to `BankPhase` the moment the
  inventory is full, or back to a fresh area search once the spot is confirmed gone. `BankPhase`
  finds a calibrated bank-marker pixel color, clicks it with a fixed offset, waits for the
  Deposit All button image (`deposit.png`) to actually appear near its known position before
  clicking it, withdraws a fresh net from one bank slot, then walks back.
- **Debug logging**: every phase transition and bank-detection outcome is timestamped and
  appended to `logs\auto-fisher-debug.log` via `lib\Log.ahk` (`auto-smith.ahk`, `auto-motherlode.ahk`,
  and `auto-fighter.ahk` log the same way to their own `logs\*-debug.log` file; the miner and
  smelter don't). Useful for diagnosing a run after the fact without relying on catching a
  tooltip live.
- **Currently**: `ENABLE_HUMANIZATION := false` (the default everywhere — flip to `true` if you
  want the subtle randomized offset/jitter back).
- **Tunables**: `COLOR_TOLERANCE=20`, `FISH_CLICK_BOX=10`, `FISH_SPOT_RADIUS=70` (the tracking
  box's half-width), `FISH_SPOT_GONE_CONFIRM_TICKS=5`, `FISH_SETTLE_MS=600`,
  `FISH_ACQUIRE_TIMEOUT_MS=10000`, `FISH_POLL_MS=150`, `FISH_TIMEOUT_MS=900000` (15 min safety
  cap — raised from an original 2 min after log evidence showed legitimate fishing sessions
  routinely taking longer), `PHASE_TIMEOUT_FISH=45000`, `BANK_MARKER_COLOR=0x0000FF`,
  `BANK_MARKER_TOLERANCE=20`, `BANK_MARKER_SEARCH_TIMEOUT_MS=8000`,
  `BANK_OPEN_SETTLE_MS=300`, `BANK_OPEN_FAILSAFE_DELAY_MS=300`, `PHASE_TIMEOUT_BANK=30000`,
  `NET_BANK_SLOT_INDEX=1`.

### `auto-miner.ahk` — mining bot
Lives in `scripts\` (promoted from a former `templates\single-ore-template.ahk` location —
see "Legacy scripts" above), built entirely from the library. Supports any number of calibrated
ore spots, checked in priority order.

- **Hotkeys**: F1 = add an ore spot (press repeatedly for more; priority = order added). F2 =
  calibrate inventory-full reference points (4 points on last slot, inventory must be empty).
  F3/F4 = record walk-to-bank / walk-back-to-mine paths. F5/F6 = start/stop. F7 = clear config.
- **Cycle**: `MinePhase` checks `oreSpots` in priority order, clicks the first one currently
  showing its ready color, then **blocks** on `WaitForPixelColorChange` for that exact spot
  before returning — this is what structurally guarantees a second ready ore can never interrupt
  the one currently being mined (the script can't even look at it while blocked). Once the last
  inventory slot is occupied, `BankPhase` walks to the bank, waits for the Deposit All button
  image to appear before clicking it, deposits everything (no withdrawal in this script), and
  walks back.
- **Currently**: `ENABLE_HUMANIZATION := false` (the default — flip to `true` for randomized
  offset/jitter).
- **Optional withdraw-after-deposit**: with `[Settings] withdrawAfterDeposit=1` in the `.ini`, the
  bank phase also withdraws one item from `WITHDRAW_AFTER_DEPOSIT_SLOT_INDEX` before walking back
  (a plain config flag, like `runMode`; defaults off). Uses the shared `BankWithdrawSlot`.
- **Tunables**: `COLOR_TOLERANCE=20`, `ORE_CLICK_BOX=12`, `ORE_DEPLETE_TIMEOUT_MS=20000`,
  `ORE_DEPLETE_CONFIRM_TICKS=2`, `PHASE_TIMEOUT_MINE=15000`, `BANK_OPEN_SETTLE_MS=300`,
  `BANK_OPEN_FAILSAFE_DELAY_MS=600`, `WITHDRAW_AFTER_DEPOSIT_SETTLE_MS=300`, `PHASE_TIMEOUT_BANK=30000`.

### `auto-smelter.ahk` — smelting bot
Lives in `scripts\`, built entirely from the library, replacing `smelter-1.ahk`'s logic.
Expected starting state: standing at the smelter with a full inventory of ore. Rebuilt to mirror
`auto-smith.ahk`'s anvil-confirm-key shape and generalized banking (see below) — it no longer
records a click into the "Smelt X" dialog, and can withdraw more than one bank slot per trip.

- **Hotkeys**: F1 = record the Smelt path (click ONLY the furnace as the last step — the
  "Smelt X" dialog is confirmed automatically via `SMELT_KEY`, not a recorded click). F2 =
  calibrate inventory reference points (same mechanism as mining's F2, but used for the opposite
  direction here — see below; samples the LAST slot, or the SECOND-TO-LAST slot if
  `checkPreviousSlot=1` — see below). F3/F4 = record walk-to-bank / walk-to-smelter paths. F5/F6 =
  start/stop. F7 = clear config.
- **Cycle**: `SmeltPhase` first checks the calibrated slot is actually occupied — if it's
  already empty (e.g. the bank ran out of ore to withdraw the previous trip), it skips straight
  to `BankPhase` instead of wastefully clicking the furnace for nothing. Otherwise it plays the
  Smelt path (furnace click only) once, presses `SMELT_KEY` to confirm the "Smelt X" dialog
  (exactly like `auto-smith.ahk`'s `AnvilPhase` pressing Space for the "make X" dialog), then
  blocks on `WaitUntilNotOccupied` until the calibrated slot goes from full to EMPTY (all ore
  consumed) — the inverse of mining's check, same underlying multi-point reference mechanism.
  `BankPhase` walks to the bank, waits for the Deposit All button image to appear before clicking
  it, deposits everything, then withdraws following `WITHDRAW_SEQUENCE` — an ORDERED array of
  `{slot, count}` entries, each clicked `count` times in a row via `BankWithdrawSlot` before
  moving to the next entry (e.g. bank slot 1 twice, then bank slot 2 once) — then walks back to
  the smelter.
- **Inventory-full reference slot is a plain `.ini` flag, not a hotkey**: `[Settings]
  checkPreviousSlot` (like `runMode`). Default `0` = F2 calibrates/checks inventory slot 28 (the
  last slot); `1` = F2 calibrates/checks slot 27 (the second-to-last) instead, for recipes/layouts
  where the very last slot never actually fills even when the inventory is otherwise full.
  Flipping this requires re-running F2 (it changes which slot gets sampled).
- **Currently**: `ENABLE_HUMANIZATION := false` (the default — flip to `true` for randomized
  offset/jitter), `WITHDRAW_SEQUENCE := [{slot:1,count:2}, {slot:2,count:1}]` (edit this array
  directly in the script to change which bank slots get withdrawn and how many times each).
- **Tunables**: `COLOR_TOLERANCE=20`, `SMELT_TIMEOUT_MS=180000` (3 min), `SMELT_CONFIRM_TICKS=2`,
  `SMELT_KEY="Space"` (or a number key like `"1"`/`"2"`/`"3"` if the dialog needs a specific bar
  selected), `SMELT_KEY_SETTLE_MS=100`, `PHASE_TIMEOUT_SMELT=30000`, `BANK_OPEN_SETTLE_MS=300`,
  `BANK_OPEN_FAILSAFE_DELAY_MS=300`, `WITHDRAW_INTER_SETTLE_MS=600`, `WITHDRAW_FINAL_SETTLE_MS=300`,
  `PHASE_TIMEOUT_BANK=30000`. No debug logging in this script (see `Log.ahk` above).

### `auto-smith.ahk` — smithing bot
Lives in `scripts\`, built entirely from the library; the newest of the four. Expected
starting state: standing near the bank, ready to withdraw bars.

- **Hotkeys**: F1 = record the walk-to-anvil path (one path covering the walk AND the anvil click
  as its last step). F2 = calibrate inventory reference points (same mechanism as the other
  scripts). F3 = record the walk-to-bank path. F5/F6 = start/stop. F7 = clear config.
- **Cycle**: `AnvilPhase` checks the last inventory slot is occupied (bars in hand) — if empty
  (e.g. the bank ran out of bars), it skips straight to `BankPhase`. Otherwise it plays the
  walk-to-anvil path, presses `Space` to confirm the "make X" dialog, then blocks on
  `WaitUntilNotOccupied` until the last slot empties (all bars smithed). `BankPhase` walks to the
  bank, deposits everything, then withdraws **two** bank slots (`WITHDRAW_SLOT_1_INDEX`,
  `WITHDRAW_SLOT_2_INDEX`) via the shared `BankWithdrawSlot`, and returns to `AnvilPhase`.
- **Currently**: `ENABLE_HUMANIZATION := false` (the default — flip to `true` for randomized
  offset/jitter).
- **Tunables**: `COLOR_TOLERANCE=20`, `ANVIL_TIMEOUT_MS=180000` (3 min), `ANVIL_CONFIRM_TICKS=3`,
  `ANVIL_SPACE_SETTLE_MS=100`, `PHASE_TIMEOUT_ANVIL=30000`, `BANK_OPEN_SETTLE_MS=300`,
  `BANK_OPEN_FAILSAFE_DELAY_MS=300`, `WITHDRAW_INTER_SETTLE_MS=600`, `WITHDRAW_FINAL_SETTLE_MS=300`,
  `PHASE_TIMEOUT_BANK=30000`. Logs to `logs\auto-smith-debug.log` via `lib\Log.ahk`.

### `auto-motherlode.ahk` — Motherlode Mine bot
Lives in `scripts\`, built entirely from the library. Unlike the other four scripts, it
does NOT use `lib\Bank.ahk` — Motherlode's deposit mechanism is a single click on a hopper marker
that triggers the game's own fully-automated run-there-and-deposit animation, not a bank-window
Deposit-All/withdraw-slot interaction. It also doesn't take a fixed-color/fixed-pixel approach to
spot detection like the legacy `motherlode-miner.ahk` (kept read-only, see "Legacy scripts" above)
— each mining spot is a colored circle overlay (corner-keyed `#0000FF` so `ImageSearch` can treat
that as transparent) whose actual rendered shade drifts depending on what's behind it, which a
single calibrated color can't reliably bracket. Detection uses the new `FindAnyImageCenter`
(`lib\Images.ahk`, see above) against pairs of reference images per state: `full.png`/
`semifull.png` (green = minable), `empty.png`/`semiempty.png` (yellow = just depleted),
`none.png`/`seminone.png` (red = nothing minable right now). Expected starting state: standing in
the mining area with an empty inventory and at least one spot visible.

- **Hotkeys**: F1/F2 = mark the two opposite corners of the calibrated mining-area search region.
  F3 = calibrate inventory-full reference points (4 points on the last slot, inventory must be
  empty). F4/F5 = mark the two opposite corners of the bank/hopper marker search region. F6 =
  record the run-back path (hopper → a mining spot, started right after the automated deposit
  run would finish). F7/F8 = start/stop. F9 = clear config.
- **Cycle**: `MinePhase` searches the mining area for a green spot and clicks it, then waits for
  it to show yellow (depleted) using the same continuously re-centering small-box tracker
  `auto-fisher.ahk`'s `FishPhase` uses (the camera pans while the character walks to/works a
  spot, so a fixed point goes stale fast) — but unlike fishing's "icon disappeared" check, this
  is an EXPLICIT positive match on the yellow images. The tracking box only re-centers on
  full/semifull matches, and the live "actively mining" timer overlay that appears right after
  clicking a spot matches neither full/semifull nor empty/semiempty (it's a 7th visual state none
  of the six reference PNGs cover) — so the box stops moving the instant mining starts and doesn't
  move again until the spot is next seen as still-green or yellow. That means the box can silently
  drift off the spot's true on-screen position for the entire mining duration if the camera pans at
  all, so the yellow/depleted check searches the WHOLE calibrated mining area, not just the
  drifted box (see bug history — a bot that sat through the full timeout without ever seeing
  yellow, even though the spot visibly turned yellow in-game, turned out to be exactly this: a
  drifted box, not a missing state). This re-opens the same "another spot elsewhere" question that
  made the green/full case unusable: a Motherlode mining area normally has several other veins
  showing green/semi-full at the same time regardless of whether the one being worked is actually
  done, so "does a different green spot exist somewhere in the area" was tried as a full/green exit
  signal and immediately proved unusable — the debug log showed it switching spots roughly once
  per second, far faster than a vein can plausibly deplete, because that condition is true almost
  continuously. Yellow is different: it's a brief, comparatively rare transition state, not a
  near-permanent one like green, so a stray yellow match elsewhere is unlikely and low-cost (worst
  case: one early re-scan that likely re-clicks the same still-active spot). There is no
  "missing -> assume depleted" fallback: a poll that matches neither full/semifull nor
  empty/semiempty is simply ignored (box stays put, wait continues) rather than counted toward
  abandoning the spot. The only ways out of the depletion wait are an explicit yellow match
  anywhere in the mining area, the inventory filling, or the hard `SPOT_DEPLETE_TIMEOUT_MS`
  safety-net timeout. The instant a spot depletes, the phase re-scans immediately for another
  green spot (no waiting for
  the next task-runner tick — same tight inner loop as `auto-miner.ahk`'s `MinePhase`) until none
  are found, at which point it checks for a red spot and stops the bot entirely if found (the
  mining flow for this area is done for now). Once the inventory fills,
  `BankPhase` searches the calibrated bank-marker area for `BANK_MARKER_COLOR` (`0xFFFF00`),
  clicks it with a fixed offset, then — since there's no "deposit done" pixel to poll for, the
  whole run-there-and-deposit sequence is automated by the game itself — just waits out a flat
  tunable/jittered `DEPOSIT_RUN_WAIT_MS` (mirrors the legacy script's hardcoded 10s `Sleep`, just
  named/tunable/jittered) before playing the recorded run-back path.
- **Debug logging**: every phase transition and bank-detection outcome is timestamped and
  appended to `logs\auto-motherlode-debug.log` via `lib\Log.ahk`.
- **Currently**: `ENABLE_HUMANIZATION := false` (the default everywhere).
- **Tunables**: `COLOR_TOLERANCE=20`, `SPOT_IMG_W=52`, `SPOT_IMG_H=52`,
  `SPOT_IMG_OPTIONS="*Trans0x0000FF *40"`, `SPOT_CLICK_BOX=12`, `SPOT_CLICK_SETTLE_MS=300`,
  `SPOT_DEPLETE_RADIUS=40` (the tracking box's half-width), `SPOT_DEPLETE_TIMEOUT_MS=60000`
  (hard safety-net timeout — the only non-yellow way out of the depletion wait),
  `SPOT_DEPLETE_CONFIRM_TICKS=2` (yellow-match confirm window), `SPOT_POLL_MS=150`,
  `PHASE_TIMEOUT_MINE=45000`,
  `BANK_MARKER_COLOR=0xFFFF00`, `BANK_MARKER_TOLERANCE=20`,
  `BANK_MARKER_CLICK_OFFSET_X=10`/`_Y=20`, `BANK_MARKER_SEARCH_TIMEOUT_MS=8000`,
  `DEPOSIT_RUN_WAIT_MS=10000` (sanity-check this against the real run+deposit time before relying
  on it unattended), `PHASE_TIMEOUT_BANK=30000`.
- **No prior working baseline**: unlike the other scripts (which replaced legacy logic the user
  could compare against directly), this is a brand-new flow built from scratch — calibrate all
  four calibrated values (mining area, inventory-full points, bank/hopper marker area, run-back
  path) in-game and run a real end-to-end cycle (spot → deplete → next spot → full → bank →
  run-back → mine again) before trusting it unattended.

### `auto-fighter.ahk` — NPC combat bot
Lives in `scripts\`, built entirely from the library. Unlike the other five scripts, this
one doesn't gather or bank anything — it just finds and fights NPCs in a loop. No path recording,
no inventory checks: the user's description of the desired behavior didn't call for either, so
neither was added.
- **The targeting problem**: NPCs are highlighted with a `#FF00FF` outline while targetable, but
  that's a ring around the sprite, not a filled shape — there's no single fixed point to search
  for the way a mining spot or fishing icon has one. `lib\Colors.ahk`'s new
  `FindNearestPixelColor` instead finds whichever outline pixel is closest to a calibrated
  character-center point, and the bot clicks just past THAT pixel (`NPC_CLICK_OFFSET_PX`, away
  from the character, along whichever axis — x or y — the outline pixel is mainly offset on) so
  the click lands inside the NPC's body instead of on the bare edge pixel between it and the
  background.
- **Hotkeys**: F1/F2 = mark the two opposite corners of the calibrated combat-area search region
  (where NPCs can appear). F3 = save the character-center point (hover the character, press F3).
  F4/F5 = start/stop. F6 = clear config.
- **Cycle**: `FightPhase` runs its own tight inner `loop` (the same pattern `auto-miner.ahk`'s
  `MinePhase` uses) instead of returning to the `TaskRunner` between scans — returning to
  `GoToPhase` and waiting for the next 150ms tick before checking again was slow enough that a
  brief/flickering outline pixel could already be gone by the next look. Each pass: find the
  outline pixel closest to the character within the combat area (re-polling every
  `NPC_SCAN_POLL_MS` and `continue`-ing immediately if nothing's found yet, rather than yielding to
  the TaskRunner), click just past it (`ATTACK_CLICK_COUNT` clicks, `ATTACK_CLICK_DELAY_MS` apart),
  then block on `WaitForPixelColor` for a single fixed indicator pixel (`COMBAT_INDICATOR_X/Y`) to
  confirm combat actually started (`COMBAT_START_COLOR`), then block again waiting for that same
  pixel to change to `COMBAT_DEAD_COLOR` (confirms the kill), then loop back immediately to re-scan
  for the next target. Both the indicator coordinate and its two colors are given directly (not
  per-NPC calibrated) since they don't depend on which NPC or where it is. If either wait times out
  (a missed click, or the NPC moved/died/was taken by someone else first), the loop just continues
  from the top instead of getting stuck. The loop only returns to the `TaskRunner` (still phase
  `"fight"`) if the runner's been stopped or the OSRS window is no longer active.
- **Currently**: `ENABLE_HUMANIZATION := false` (the default everywhere).
- **Tunables**: `COLOR_TOLERANCE=20`, `NPC_OUTLINE_COLOR=0xFF00FF`, `NPC_SEARCH_STEP_PX=30`,
  `NPC_SCAN_POLL_MS=30` (re-scan interval inside `FightPhase`'s own loop when nothing's found yet —
  deliberately tighter than the TaskRunner's 150ms tick), `NPC_CLICK_OFFSET_PX=3`,
  `ATTACK_CLICK_COUNT=1`, `ATTACK_CLICK_DELAY_MS=10`, `ATTACK_CLICK_BOX=0`, `ATTACK_SETTLE_MS=200`,
  `COMBAT_INDICATOR_X=1657`, `COMBAT_INDICATOR_Y=1232`, `COMBAT_START_COLOR=0x068C37`,
  `COMBAT_DEAD_COLOR=0x651312`, `COMBAT_START_TIMEOUT_MS=3000`, `COMBAT_KILL_TIMEOUT_MS=120000`,
  `COMBAT_CONFIRM_TICKS=2`, `COMBAT_POLL_MS=100`, `PHASE_TIMEOUT_FIGHT=150000`.
- **No prior working baseline**: this is a brand-new flow, not a port of anything. Calibrate both
  F-key values in-game and run a real fight (find → click → combat starts → kill confirmed → next
  target) before trusting it unattended, and sanity-check the indicator coordinate/colors against
  your own UI scale/setup.

All five gathering/processing scripts' `.ini` files live in `config\` and use the same section conventions:
`[InventoryEmptyPoints]` (4-point list), `[Settings] runMode`, and one section per recorded path
(`[ToBank]`, etc., each with `count` + `step{i}_*` keys). The miner may have several `.ini`
profiles (e.g. one per ore) that share the single `auto-miner.ahk` file — `config\miner-m-iron.ini`
is the one `CONFIG` (line ~94) currently points to; `config\miner-nm.ini` is a second saved
profile for a different spot/ore, not currently active. Swap which file `CONFIG` points to (and
re-run the F1/F2/F3 calibration if it's actually a different physical location) to switch profiles.

---

## Bugs found and fixed during this project (useful troubleshooting history)

1. **No timeout on blocking wait loops** in all 3 legacy scripts → every `Wait*` function in
   `Colors.ahk` now requires a `timeoutMs`.
2. **No game-window-focus check anywhere** → `Safety.ahk`'s `RequireOsrsWindowActive`, called
   first in every phase.
3. **No coordinate/region bounds validation** → `Safety.ahk`'s `IsCoordOnScreen`/`IsRegionValid`,
   used by `Validate.ahk`.
4. **Zero click/delay randomization** → `Click.ahk`'s `HumanClick`/`JitterDelay`, toggleable via
   `ENABLE_HUMANIZATION`.
5. **Two incompatible recorded-path formats** between miner-3/motherlode (separate "first click"
   fields) and smelter-1 (first click as a normal step) → one canonical format in `Paths.ahk`.
6. **Corner-vs-center coordinate bug** (found during initial `Grid.ahk` build): the deposit
   button's coordinate was correctly treated as a top-left corner and converted to center, but
   inventory/bank slot coordinates were initially used directly AS centers — inconsistent with
   how the user described all three the same way. This made every inventory-full check sample a
   point ~36px off from the true slot center (almost always plain background, so it could never
   detect "full"), and made roughly half of randomized bank-slot clicks land outside the slot
   box. Fixed by treating all three the same way (corner + size → converted to center).
7. **Spam-clicking the same ore** (mining): `MinePhase` originally re-checked and re-clicked the
   ore pixel every ~150ms tick with no wait, which interrupts mining in OSRS (re-clicking
   something you're already mining cancels the action) — meaning the rock never actually
   depleted and the inventory never filled. Fixed by clicking once then **blocking** on
   `WaitForPixelColorChange` before allowing another click.
8. **Phase-timeout-while-working bug** (introduced by fix #7, then caught): `TaskRunner`'s
   per-phase timeout was measured from when the phase was entered and never reset just because
   the phase returned its own name again — so a bot mining successfully for longer than
   `PHASE_TIMEOUT_MINE` would eventually self-stop thinking it was stuck. Fixed with
   `ResetPhaseTimer`, called after every successful click/attempt.
9. **False-positive "rock depleted" right after returning from the bank**: a single transient
   pixel blip (character/camera settling) could be misread as "the rock just changed" almost
   instantly, causing the bot to move on to a second ore spot before the first was actually
   done. Fixed with the `confirmTicks` debounce in `WaitForPixelColorChange` (and the matching
   `WaitUntilOccupied`/`WaitUntilNotOccupied`) — require N consecutive polls to agree before
   trusting a state change.
10. **Fishing-spot tracking broke for any real walking distance** (mining's fixed-pixel approach
    doesn't transfer to fishing): the camera follows the character while it walks toward a spot
    that isn't adjacent, so the spot's on-screen position keeps drifting continuously for the
    WHOLE walk, not just briefly after the click. A one-time "wait, then lock onto a fixed point"
    approach went stale almost immediately; checking the WHOLE calibrated area continuously had
    the opposite failure (something is almost always visible somewhere in the area, so "gone" was
    never detected and the bot never switched to a new spot). Fixed with the continuously
    re-centering small-box tracker described in the `auto-fisher.ahk` section above — confirmed
    correct via debug-log evidence across several iterations.
11. **Bot silently went idle after a fishing spot moved**: same root cause as #8, but for the
    "spot confirmed gone" conclusion specifically — returning the same phase name ("fish") to
    re-search does NOT reset the phase timer, so without an explicit `ResetPhaseTimer` call right
    before that return, the next tick could see the phase as already timed out. Fixed by adding
    that call alongside the one from fix #8.
12. **Blind fixed-delay waits for the bank to open** (the real scripts originally): guessing how
    long a walk + bank-open animation takes is fragile — too short risks clicking before the
    Deposit All button exists, too long wastes time every single cycle. Fixed across all the
    scripts with `deposit.png` + `lib\Images.ahk`'s `WaitForImageNearButton`: poll for the actual
    button image near its known position, bounded by `BANK_OPEN_TIMEOUT_MS`, with a small settle
    delay before polling starts and a small fail-safe delay after the click — both configurable,
    both apply every time regardless of how fast detection succeeds.
13. **`auto-smelter.ahk` clicked the furnace and smelt-all button even with an empty inventory**
    (e.g. right after the bank ran out of ore to withdraw): unlike mining/fishing, which only ever
    click after confirming a target is present, `SmeltPhase` unconditionally played the smelt
    path every phase entry. Fixed by adding an `IsAnyPointOccupied` check at the top of the phase
    that skips straight to `BankPhase` if the last inventory slot already reads empty.
14. **Unbounded humanization scaling**: click offset and delay jitter scaled with whatever box
    size or base delay a call site happened to pass in (e.g. up to ±36px for a 72px-wide bank
    slot, or jitter scaling with an 800ms+ delay), with no ceiling. Fixed with
    `MAX_CLICK_OFFSET_PX`/`MAX_DELAY_JITTER_MS` hard caps in `Click.ahk`, applied via `Min()`
    regardless of call-site parameters, plus making sure every real script explicitly sets
    `ENABLE_HUMANIZATION := false` rather than silently inheriting the library default.
15. **Bank deposit/withdraw logic was copy-pasted into all four `BankPhase`s and drifted**: the
    post-withdraw settle was a named tunable (300) in the miner but a bare `800` literal elsewhere,
    and the smith had a unique bare `400` between its two withdrawals — same operation, inconsistent
    constants, easy to break one script while editing another. Extracted into `lib\Bank.ahk`
    (`BankDepositAll` / `BankWithdrawSlot`) so every script's banking is one shared implementation;
    each script passes only its own deliberately-tuned settle/failsafe delays. Behavior-preserving
    (the per-script delay values were kept exactly), just no longer duplicated.
16. **`auto-motherlode.ahk` abandoned a spot it was actively mining, switching to a different
    green spot right after clicking**: a freshly-clicked spot (especially one that started as
    `full.png`, not `semifull.png`) shows a live "timer" depletion overlay while being mined that
    matches neither the full/semifull images nor the empty/semiempty ones — a 7th visual state
    none of the six reference PNGs cover. The depletion-wait loop had a `missingStreak` fallback
    that treated several consecutive "matched neither" polls as "the spot vanished, assume
    depleted" — first tried with a longer confirm threshold than the yellow check, but the
    underlying assumption was wrong regardless of the threshold: "matched neither" during active
    mining is normal and tells you nothing about depletion. Fixed by removing the fallback
    entirely — a poll that matches neither full/semifull nor empty/semiempty is now just ignored
    (box stays put, wait continues). The depletion wait now only ends on an explicit yellow match,
    the inventory filling, or the hard `SPOT_DEPLETE_TIMEOUT_MS` safety-net timeout.
17. **After fix #16, the bot appeared to sit motionless on a depleted spot instead of moving on**
    (one `mine: found minable spot...` log line, then nothing until the user force-stopped it 39
    seconds later). Tried adding a second "move on" signal: if a different full/semifull spot
    appears anywhere else in the mining area while waiting, treat that as just as valid a reason
    to stop waiting as an explicit yellow match at the tracked spot. This immediately backfired —
    see fix #18 — so it was reverted. (The real root cause turned out to be unrelated to "another
    spot appearing" at all — see fix #19.)
18. **The fix from #17 made the bot switch spots roughly once per second** — confirmed via the
    debug log, which showed `mine: another minable spot appeared at ... - moving on` firing every
    1-5 seconds, far too fast for a vein to actually deplete. Root cause: a Motherlode mining area
    normally has several OTHER veins showing green/semi-full at the same time regardless of
    whether the one currently being worked is done, so "does a different green spot exist
    somewhere in the area" is true almost continuously and was never a meaningful "this one is
    done" signal — unlike fix #16's removed `missingStreak` fallback (a true false-positive from
    matching the wrong thing), this one was matching the *right* thing, just asking the *wrong
    question*. Fixed by reverting #17 entirely: the depletion wait now only ends on an explicit
    yellow match at the exact tracked spot, the inventory filling, or the hard
    `SPOT_DEPLETE_TIMEOUT_MS` safety net — full stop, no secondary signal of any kind.
19. **After reverting #17/#18, the bot went back to never switching spots at all** — same
    "sits there until the hard timeout" symptom as #17, just without a workaround this time. Root
    cause: the depletion-wait's tracking box only re-centers (`cx`/`cy` update) on a full/semifull
    match, but while a spot is actively being mined it shows the 7th-state timer overlay (see #16)
    that matches neither full/semifull nor empty/semiempty — so `cx`/`cy` freeze at the position
    the spot was at the *moment it was clicked* and never move again for the entire mining
    duration. If the camera pans at all during that time (confirmed elsewhere in this file that it
    does), the small tracking box silently drifts off the spot's real on-screen position, so the
    yellow/depleted match — which was only ever searched for inside that box — could miss forever,
    even though the spot genuinely turned yellow on-screen exactly when expected. This is almost
    certainly what #17 actually was too: not a slow vein, a drifted box. Fixed by searching the
    WHOLE calibrated mining area for empty/semiempty instead of the drifted box (the full/semifull
    re-centering check is unchanged — still box-scoped, since that's only used for tracking, not
    for ending the wait). This re-opens the "another spot elsewhere" question fix #18 ruled out for
    green, but yellow doesn't have green's problem: green is shown by several other veins
    continuously, yellow is a brief, comparatively rare transition, so a stray match elsewhere is
    unlikely and low-cost (worst case: one early re-scan, probably re-clicking the same still-active
    spot).

## Testing notes

AutoHotkey v2 is installed at `C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe` on this machine.
To syntax-check a `lib\*.ahk` file (function-only, no hotkeys) without it staying resident:

```powershell
& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut "path\to\file.ahk"
```

It loads, finds no executable top-level code, and exits on its own — any output means a load
error. A real script (with hotkeys) will stay resident; launch it with a `System.Diagnostics
.Process`, wait ~2s, confirm it's still running (= loaded with no fatal error) with no stdout/
stderr output, then `Kill()` it. **Be careful**: if the user might already have one of these
scripts running live for their own testing, don't blindly kill every AHK process you find —
check window titles/command lines first, and when in doubt, leave it alone (an idle script with
hotkeys registered but the bot not started is harmless either way).
