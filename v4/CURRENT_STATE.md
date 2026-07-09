# v4 OSRS Automation Framework — Current State

_Last updated: 2026-07-09_

## What this is

`v4/` is a from-scratch, native OOP AutoHotkey v2 rewrite of the OSRS automation framework, built alongside the legacy `lib/`/`scripts/`/`config/` codebase (never modifying it — legacy is read-only reference material). The goal: decouple timing from action logic, classify detection into clean primitives (dynamic color targets / static UI anchors / lightweight telemetry gates), and make every bot's behavior fully config-driven instead of scattered across hardcoded constants and inline `Sleep` calls.

## What works right now

**The Motherlode Mine bot's mining phase is fully working and verified live in-game.** It finds a vein, walks to it, mines it, detects depletion, and re-acquires a new vein — with a real settle delay before each click (so OSRS registers a genuine vein interaction, not a plain tile click), a window-focus safety gate, and a live on-screen status overlay.

Everything else (banking, return-to-mine, other bots) is **not yet built**. When the inventory fills up, the bot correctly logs "Inventory full, transitioning to clearRed" and then stops itself, because the `clearRed` phase doesn't exist yet.

### File tree (23 files)
```
v4/
├── Core/           Engine.ahk, EngineContext.ahk, FailSafe.ahk, Phase.ahk
├── Timing/         Waiter.ahk, TimingProfile.ahk, Clock.ahk (unused stub)
├── Detection/      ColorSearch.ahk, TargetLock.ahk, Telemetry.ahk,
│                   DynamicTarget.ahk (partially unused), StaticAnchor.ahk (unused stub)
├── Actions/        Click.ahk, Humanizer.ahk, KeyAction.ahk (unused stub)
├── Interfaces/     Inventory.ahk, Bank.ahk (unused stub), Walk.ahk (unused stub)
├── Config/         Config.ahk
├── Diagnostics/     Logger.ahk, WindowFocus.ahk, Overlay.ahk
├── Bots/Motherlode/ motherlode.ahk  ← the only bot; entry point + MinePhase class in one file
├── config/         auto-motherlode-v2.ini  ← v4's own config, isolated from legacy's
└── logs/           auto-motherlode-v4-debug.log  ← generated at runtime, isolated from legacy's
```

The "unused stub" files are intentional forward-looking scaffolding for phases not yet built (bank deposit, waypoint walking, image-anchor detection, key-press actions) — confirmed via a full audit, not dead/forgotten code.

## Architecture recap

- **Engine / Phase**: a named-phase state machine (`Engine.Tick()` calls the current `Phase.Run(ctx)`, which returns the next phase's name). Direct OOP port of legacy's `TaskRunner.ahk`.
- **EngineContext**: the one state bag passed into every phase — `ctx.clicker`, `ctx.waiter`, `ctx.timing`, `ctx.inventory`, `ctx.windowFocus`, `ctx.overlay`, plus `ctx.Get`/`Set` scratch state and a `ctx.Log(text)` that fans out to both the file logger and the on-screen overlay.
- **Timing**: `Waiter.After(profile, key)` is the *only* place `Sleep` is called anywhere in v4 — every delay is a named `.ini` key, never a bare number in phase code.
- **Detection**: `ColorSearch.FindFilledBlock` (dynamic color-block search, with an optional bottom-up scan direction), `TargetLock` (stability debounce — position always updates live, "stable" is a separate side-flag), `SlotGate` (inventory occupancy via hardcoded empty-color comparison).
- **Actions**: `Clicker.MoveTo(x,y)` + `Clicker.Press()` as two separate steps (so a settle delay can sit between them), plus a `ClickAt`/`ClickAtWithCtrl` convenience wrapper for callers that don't need the delay.
- **Config**: `Config.Load()` reads every declared `.ini` key up front and throws immediately (listing *all* missing keys at once) if anything's absent — no silent fallback to a code-side default, ever.

## Bugs found and fixed this session (for context on what to watch for)

1. **AHK v2 naming collision**: `foo := ClassName(...)` fails to load if `foo` case-insensitively matches the class name. Every constructor call site in v4 is prefixed (`botConfig`, `botLogger`, etc.) to avoid this.
2. **Method-name collision with an AHK builtin**: a class method literally named `Click()` calling the builtin `Click()` function inside itself gets parsed as self-recursion. Fixed by renaming to `ClickAt`/`Press` — **never name a method the same as a builtin it needs to call.**
3. **The big one — implicit `this` on stored function properties**: `this._someFn(a, b)` is parsed by AHK v2 as *a method call*, silently injecting `this` as a hidden extra argument — even when `_someFn` just holds a plain function object. This caused "Too many parameters passed to function" and broke the click-settle delay for a while. Fix: assign to a local first (`fn := this._someFn; fn(a, b)`) before calling.
4. **Missing `CoordMode`**: AHK v2 defaults `Click`/`MouseMove`/`PixelSearch` coordinates to "Client" (relative to the focused window), not "Screen." v4 now sets all three `CoordMode` calls at startup, matching legacy.
5. **Click registering as a plain tile click, not a vein interaction**: root cause was v4 firing `MouseMove` + `Click` back-to-back with zero delay, while legacy always sleeps ~150ms in between so the game client has time to register hover/highlight state. Fixed by properly wiring `Waiter` into the click path (`clickSettleMs` in the `.ini`).
6. Also fixed along the way: a click-center regression from an over-corrected block-centering algorithm, a scan-direction bug where "bottom-up" search silently fell back to top-down, `VerifyBlock` not being direction-aware, and a stuck-after-one-click bug when a vein's position never stabilizes.

## What's fully config-driven now (nothing hardcoded except inventory layout)

`v4/config/auto-motherlode-v2.ini` drives: tick rate, phase timeout, color tolerance, stability ticks, click cooldown, click offset, scan direction, re-click timeout, click settle delay + jitter, Ctrl-hold settle, **vein search region** (`mineRegionX1/Y1/X2/Y2`), **vein colors** (`veinColorLight/Dark`), **detection block size** (`mineBlockW/H`), **reference point** (`referencePointX/Y`), run mode, and indicator slot.

The **inventory layout** (`firstX=2099, firstY=801, 4×7 grid, 72×64 cells, 12/8px gaps`) is deliberately a hardcoded `Map` inside `motherlode.ahk`, not an `.ini` key — it's a fixed property of this user's client window, not a gameplay tunable, matching how legacy's `lib/Grid.ahk` treats its own `INVENTORY_FIRST_X` etc. as hardcoded constants.

## Prompt for continuing this work in a future session

> I'm continuing work on `v4/`, a from-scratch AHK v2 OOP rewrite of an OSRS automation framework, living alongside a read-only legacy codebase (`lib/`, `scripts/`, `config/` at the repo root — never modify these, they're reference material only). Read `v4/CURRENT_STATE.md` first for full context: what's built, what's config-driven, and a list of AHK v2 gotchas already discovered (implicit-`this` on stored function properties, method-name collisions with builtins, the `CoordMode` default, etc. — don't rediscover these the hard way).
>
> The Motherlode Mine bot's `mine` phase is fully working and verified live in-game. Next up is porting the remaining phases from `scripts/auto-motherlode-v2.ahk` (`clearRed`, `clearYellow`, `withdrawSack`, `depositBank`, `returnMine1`, `returnMine2`) into `v4/Bots/Motherlode/motherlode.ahk`, following the same pattern already established for `MinePhase`: a `class XPhase extends Phase`, config-driven values (no hardcoded coordinates/colors/timings — everything through `v4/config/auto-motherlode-v2.ini`), routed through the same four contracts (`Detection`/`Timing`/`Actions`/`Telemetry` — never a raw `Sleep`/`Click`/`PixelGetColor` call in phase code), and verified by actually running the script (`AutoHotkey64.exe /ErrorStdOut`) before declaring anything done — load-check first, then a real F5 trigger, then check the log, not just a read-through.
>
> Some already-built stub files (`Interfaces/Bank.ahk`, `Interfaces/Walk.ahk`, `Detection/StaticAnchor.ahk`) are forward-looking scaffolding meant for exactly these next phases — check whether they're actually usable as-is or need adjusting before building new logic from scratch.
