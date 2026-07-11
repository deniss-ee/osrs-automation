# v4 OSRS Automation Framework — Current State

_Last updated: 2026-07-11_

## What this is

`v4/` is a from-scratch, native OOP AutoHotkey v2 rewrite of the OSRS automation framework, built alongside the legacy `lib/`/`scripts/`/`config/` codebase at the repo root (never modified — read-only reference material). Every bot's behavior is fully config-driven (`.ini`-backed, nothing hardcoded except the one sanctioned exception — inventory pixel-grid layout), every delay routes through `Waiter.After(profile, key)` (the only place `Sleep()` is called), and every phase follows the same `Phase.Run(ctx) -> nextPhaseName` state-machine contract.

For the full architectural reference (every shared class, gate, pattern, and known gotcha) see **`v4/ARCHITECTURE.md`** — that document is the primary lookup reference; this one is a status snapshot.

## What works right now

**Four bots exist, all fully built and load-check verified; three (Motherlode, Firemaking, Smelter) are live-verified in-game across multiple cycles. Smithing was just built and had one live-tested bug fix (a miscalibrated bank-marker color) — needs another live pass to confirm the fix holds.**

- **Motherlode** (`v4/Bots/Motherlode/motherlode.ahk`) — 7 phases: `mine -> clearRed -> clearYellow -> withdrawSack -> depositBank -> returnMine1 -> returnMine2 -> mine`. The most complex bot; uses `TargetLock`-based acquire/track stability tracking, not shared with any other bot.
- **Firemaking** (`v4/Bots/Firemaking/firemaking.ahk`) — 4 phases: `goToFire -> burnLogs -> goToBank -> withdrawLogs -> goToFire`. Uses both shared generic phases (`PressAndWaitEmptyPhase`, `GoToBankPhase`).
- **Smelter** (`v4/Bots/Smelter/smelter.ahk`) — 4 phases: `goToFurnace -> smelt -> goToBank -> depositAndWithdraw -> goToFurnace`. Two `.ini` variants exist (`smelter-gold.ini`, `smelter-mithril.ini` in `v4/config/`) — same code, different calibration/withdraw-plan per metal. `smelt` is bot-specific (uses `SlotSignatureGate`, not the shared `PressAndWaitEmptyPhase`) because ore→bar doesn't empty the indicator slot the way logs do.
- **Smithing** (`v4/Bots/Smithing/smithing.ahk`) — 4 phases: `goToAnvil -> smith -> goToBank -> depositAndWithdraw -> goToAnvil`. Uses `PressAndWaitEmptyPhase` (bars fully disappear from the slot, unlike Smelter's ore→bar transform).

### File tree

```
v4/
├── Core/            Engine, EngineContext, FailSafe, Phase, SharedPhases (generic reusable phases)
├── Timing/           Waiter, TimingProfile, Clock.ahk (unused stub)
├── Detection/        ColorSearch, TargetLock, Telemetry (incl. SlotSignatureGate, now implemented),
│                     StaticAnchor, DynamicTarget (unused stub)
├── Actions/          Click (incl. ClickSettled), Humanizer, KeyAction
├── Interfaces/       Inventory, Bank, Walk (unused stub)
├── Config/           Config.ahk
├── Diagnostics/      Logger, WindowFocus, Overlay
├── Bots/
│   ├── Motherlode/   motherlode.ahk
│   ├── Firemaking/   firemaking.ahk
│   ├── Smelter/      smelter.ahk
│   └── Smithing/     smithing.ahk
├── config/           auto-motherlode-v2.ini, auto-firemaking-v2.ini,
│                     smelter-gold.ini, smelter-mithril.ini, auto-smithing-v2.ini
├── logs/             auto-<bot>-v4-debug.log — generated at runtime, isolated from legacy's
├── ARCHITECTURE.md   primary lookup reference — classes, gates, patterns, gotchas
└── CURRENT_STATE.md  this file — status snapshot
```

`DynamicTarget.ahk`, `Walk.ahk`, `Clock.ahk` remain genuinely unused scaffolding (confirmed via grep across all 4 bots) — not dead/forgotten, just not yet needed by any bot built so far. See `ARCHITECTURE.md`'s "Known stubs" section for the up-to-date list.

## Session-long fixes worth remembering (AHK v2 gotchas + recurring bug classes)

1. **AHK v2 naming collision**: `foo := ClassName(...)` fails to load if `foo` case-insensitively matches the class name. Every constructor call site is prefixed (`botConfig`, `botLogger`, etc.).
2. **Method-name collision with an AHK builtin**: a method literally named `Click()` calling the builtin internally self-recurses. Fixed by naming it `Press`/`ClickAt` instead.
3. **Implicit `this` on stored function properties**: `this._someFn(a, b)` parses as a method call, silently injecting `this` as a hidden extra arg. Fix: assign to a local first, then call it.
4. **`CoordMode` defaults to "Client"** in AHK v2, not "Screen" — every bot sets all three `CoordMode` calls (Mouse/Pixel/ToolTip) to "Screen" at startup.
5. **The recurring "instant click/search right after a fresh detection, no settle delay" bug class** — hit independently at least 5 times across Motherlode, Firemaking, and Smithing (most recently: a bank-marker miscalibration in Smithing masked as this same symptom, though the actual root cause there was a wrong color value, not a missing delay — see `ARCHITECTURE.md`'s "concrete miscalibration bug" note). Standard fix pattern: a config-driven settle delay applied once via a scratch-state flag, reset at the same point every other per-cycle scratch state resets.
6. **A slot that changes appearance without becoming empty** (Smelter's ore→bar) breaks any `IsEmpty()`-based "done" check — this is why `SlotSignatureGate` (baseline-snapshot-then-diff) exists as a distinct gate from `SlotGate`/`NotGate`. Before assuming a new bot's "wait until done" step can reuse `PressAndWaitEmptyPhase`, confirm the crafted/consumed item actually vanishes from the indicator slot rather than just changing appearance in place.

## Verification methodology used throughout

For every code change: load-check via `AutoHotkey64.exe /ErrorStdOut` (`PowerShell`'s `Start-Process ... -PassThru`, sleep ~1.5s, check `$p.HasExited` — `False` means it loaded cleanly and is idle waiting for F5), then a real F5 trigger in-game, then check the bot's own debug log — never just a read-through. Several real bugs (the Smithing bank-marker color, the Smelter ore→bar empty-check) were only caught this way, not by static review.

## Prompt for continuing this work in a future session

> Continuing work on `v4/`, a from-scratch AHK v2 OOP rewrite of an OSRS automation framework, living alongside a read-only legacy codebase (`lib/`, `scripts/`, `config/` at the repo root — never modify these). Read `v4/ARCHITECTURE.md` first (primary reference: every shared class, gate, pattern, and gotcha) and `v4/CURRENT_STATE.md` (this file, status snapshot) before starting anything.
>
> Four bots exist (Motherlode, Firemaking, Smelter, Smithing), all load-check verified; Motherlode/Firemaking/Smelter are live-verified across multiple cycles, Smithing needs one more live pass after its bank-marker-color fix. A cross-bot unification pass consolidated duplicated click/phase code into `Clicker.ClickSettled` and `Core/SharedPhases.ahk` — read that section of `ARCHITECTURE.md` before writing a new bot's phases by hand, since two of the four phase shapes are already generic and reusable.
>
> Standing rules: every pause/delay/coordinate/color/threshold is `.ini`-backed, nothing hardcoded in phase code (one sanctioned exception: inventory pixel-grid layout, a fixed client-window property). Every delay routes through `Waiter.After(profile, key)` — never a bare `Sleep`. `Config.Load()` fails fast listing every missing key at once. Verify every change by loading it (`AutoHotkey64.exe /ErrorStdOut`), not just reading the code — several real bugs this session were only caught live.
>
> A `v4/Config/Bank.ahk`-based multi-slot withdraw-plan pattern (`.ini` keys `withdrawSlotCount` + `withdrawSlot<i>Index`/`withdrawSlot<i>Clicks`) is established and reusable for any bot that withdraws from more than one bank slot or needs repeat clicks on one slot.
