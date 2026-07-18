# osrs-automation Framework — Current State

_Last updated: 2026-07-17_

## What this is

A native OOP AutoHotkey v2 automation framework for OSRS. Every bot's behavior is fully config-driven (`.ini`-backed, nothing hardcoded except the one sanctioned exception — inventory pixel-grid layout), every delay routes through `Waiter.After(profile, key)` (the only place `Sleep()` is called), and every phase follows the same `Phase.Run(ctx) -> nextPhaseName` state-machine contract.

For the full architectural reference (every shared class, gate, pattern, and known gotcha) see **`ARCHITECTURE.md`** — that document is the primary lookup reference; this one is a status snapshot.

Every bot now has its own `Bots/<Name>/README.md` — full state-machine breakdown, config reference, known risks/edge cases, and a future-development roadmap, written from a fresh audit of each bot's actual current code. Read a bot's own README before extending it; this file stays a short cross-bot snapshot.

## What works right now

**Nine bots exist, all fully built and load-check verified. Motherlode/Firemaking/Smelter/Smithing/AutoFighter are live-verified in-game across multiple cycles. FruitStall is the newest — live-verified end-to-end this session (stall click, loot-slot detection, detected-theft handoff to combat, kill confirmation, resume) after fixing three latent bugs in the shared `WaitCombatPhase` along the way.**

- **Motherlode** (`Bots/Motherlode/motherlode.ahk`) — 7 phases: `mine -> clearRed -> clearYellow -> withdrawSack -> depositBank -> returnMine1 -> returnMine2 -> mine`. The most complex bot; uses `TargetLock`-based acquire/track stability tracking over a walking multi-tile course, not shared with any other bot. **Audit finding**: water wheel repair is entirely unimplemented — no color/marker/phase anywhere references it; a broken wheel in-game would loop-timeout after 30s with no explicit diagnosis. See `Bots/Motherlode/README.md`.
- **MotherlodeFixed** (`Bots/MotherlodeFixed/motherlode-fixed.ahk`) — 3 phases: `mine -> depositBank -> returnToMine -> mine`. Not a bugfix of plain Motherlode — a structural rewrite for a stand-still setup where two pay-dirt veins are always visible at fixed points (no walking course, no hopper/sack, no rockfalls). Coexists with plain Motherlode; separate `.ini`, separate log, no shared code between the two. See `Bots/MotherlodeFixed/README.md`.
- **Firemaking** (`Bots/Firemaking/firemaking.ahk`) — 4 phases: `goToFire -> burnLogs -> goToBank -> withdrawLogs -> goToFire`. Uses both shared generic phases (`PressAndWaitEmptyPhase`, `GoToBankPhase`). **Audit finding**: always lights fires at the same fixed screen spot every cycle with no relocation logic — a real risk of an occupied-tile failure over an extended run. See `Bots/Firemaking/README.md`.
- **Smelter** (`Bots/Smelter/smelter.ahk`) — 4 phases: `goToFurnace -> smelt -> goToBank -> depositAndWithdraw -> goToFurnace`. Two `.ini` variants exist (`smelter-gold.ini`, `smelter-mithril.ini`) — same code, different calibration/withdraw-plan values per metal (switching variants currently means editing the hardcoded `iniPath` line in `smelter.ahk`, not a runtime flag). `smelt` is bot-specific (uses `SlotSignatureGate`, not `PressAndWaitEmptyPhase`) because ore→bar doesn't empty the indicator slot the way logs do. **Audit finding**: `Calibrate()` runs *after* a 100ms settle delay rather than before it, risking a baseline snapshot of the wrong (already-transforming) slot state. See `Bots/Smelter/README.md`.
- **Smithing** (`Bots/Smithing/smithing.ahk`) — 4 phases: `goToAnvil -> smith -> goToBank -> depositAndWithdraw -> goToAnvil`. Uses `PressAndWaitEmptyPhase` (bars fully disappear from the slot, unlike Smelter's ore→bar transform). The historical `bankMarkerColor` magenta/blue miscalibration bug is confirmed still fixed in the live `.ini`. See `Bots/Smithing/README.md`.
- **AutoFighter** (`Bots/AutoFighter/autofighter.ahk`) — 2 phases: `scanAndAttack -> waitCombat -> scanAndAttack`. No bank/inventory step — scans a bounded region around a reference point for the nearest irregular NPC-overlay blob (`ColorSearch.FindNearestBlobCenter`), clicks it, then polls a raw combat-indicator pixel (`PixelColorGate`) for a start/kill color pair. Both phases now live in `Core/SharedPhases.ahk` (`ScanAndAttackPhase`, `WaitCombatPhase`), shared with AutoFighterLoot and (for `WaitCombatPhase`) FruitStall. See `ARCHITECTURE.md`'s dedicated section and `Bots/AutoFighter/README.md`.
- **AutoFighterLoot** (`Bots/AutoFighterLoot/autofighter-loot.ahk`) — 3 phases: `scanAndAttack -> waitCombat -> lootPickup -> scanAndAttack`. AutoFighter's two shared phases plus a bot-specific `LootPickupPhase` (right-click dropped item, click take-menu option, click inventory slot 1). A missed loot pickup logs and continues rather than stopping the engine. **Audit finding**: doesn't pass a `retryNextPhaseName`, so a missed attack click routes through `lootPickup`'s own wait chain before resuming scanning, instead of retrying immediately like plain AutoFighter. See `Bots/AutoFighterLoot/README.md`.
- **FruitStall** (`Bots/FruitStall/fruitstall.ahk`) — 2 phases: `thieving -> waitCombat -> thieving`. Click a stall's ready-pixel, wait for inventory slot 1 to fill (stolen loot); no loot within a timeout means detected, hand off to the shared `WaitCombatPhase` with no attack click (the NPC auto-attacks on approach). Newest bot, built and live-debugged this session. **Audit finding**: no explicit "is slot 1 actually empty" check before trusting a fresh steal — a missed prior loot-click or a full inventory could produce a false "loot detected" that masks a real theft-detection event. See `Bots/FruitStall/README.md`.

### File tree

```
.
├── Core/            Engine, EngineContext, FailSafe, Phase, SharedPhases (generic reusable phases,
│                     incl. ScanAndAttackPhase/WaitCombatPhase shared by 3 bots)
├── Timing/           Waiter, TimingProfile, Clock.ahk (unused stub)
├── Detection/        ColorSearch (incl. FindNearestBlobCenter), TargetLock,
│                     Telemetry (incl. SlotSignatureGate, PixelColorGate), StaticAnchor,
│                     DynamicTarget (unused stub)
├── Actions/          Click (incl. ClickSettled), Humanizer, KeyAction
├── Interfaces/       Inventory, Bank, SlotSignature, Walk (unused stub)
├── Config/           Config.ahk, auto-motherlode-v2.ini, auto-firemaking-v2.ini,
│                     smelter-gold.ini, smelter-mithril.ini, auto-smithing-v2.ini,
│                     auto-fighter-v2.ini, auto-fighter-loot.ini, auto-agility.ini,
│                     auto-fruitstall.ini, and MotherlodeFixed's own .ini
├── Diagnostics/      Logger, WindowFocus, Overlay
├── Bots/
│   ├── Motherlode/      motherlode.ahk, README.md
│   ├── MotherlodeFixed/ motherlode-fixed.ahk, README.md
│   ├── Firemaking/      firemaking.ahk, README.md
│   ├── Smelter/         smelter.ahk, README.md
│   ├── Smithing/        smithing.ahk, README.md
│   ├── AutoFighter/     autofighter.ahk, README.md
│   ├── AutoFighterLoot/ autofighter-loot.ahk, README.md
│   ├── Agility/         agility.ahk, README.md
│   └── FruitStall/      fruitstall.ahk, README.md
├── logs/             auto-<bot>-v4-debug.log — generated at runtime
├── ARCHITECTURE.md   primary lookup reference — classes, gates, patterns, gotchas
└── CURRENT_STATE.md  this file — status snapshot
```

`DynamicTarget.ahk`, `Walk.ahk`, `Clock.ahk` remain genuinely unused scaffolding — not dead/forgotten, just not yet needed by any bot built so far. See `ARCHITECTURE.md`'s "Known stubs" section for the up-to-date list.

## Session-long fixes worth remembering (AHK v2 gotchas + recurring bug classes)

1. **AHK v2 naming collision**: `foo := ClassName(...)` fails to load if `foo` case-insensitively matches the class name. Every constructor call site is prefixed (`botConfig`, `botLogger`, etc.).
2. **Method-name collision with an AHK builtin**: a method literally named `Click()` calling the builtin internally self-recurses. Fixed by naming it `Press`/`ClickAt` instead.
3. **Implicit `this` on stored function properties**: `this._someFn(a, b)` parses as a method call, silently injecting `this` as a hidden extra arg. Fix: assign to a local first, then call it.
4. **`CoordMode` defaults to "Client"** in AHK v2, not "Screen" — every bot sets all three `CoordMode` calls (Mouse/Pixel/ToolTip) to "Screen" at startup.
5. **The recurring "instant click/search right after a fresh detection, no settle delay" bug class** — hit independently at least 5 times across Motherlode, Firemaking, and Smithing (most recently: a bank-marker miscalibration in Smithing masked as this same symptom, though the actual root cause there was a wrong color value, not a missing delay — see `ARCHITECTURE.md`'s "concrete miscalibration bug" note). Standard fix pattern: a config-driven settle delay applied once via a scratch-state flag, reset at the same point every other per-cycle scratch state resets.
6. **A slot that changes appearance without becoming empty** (Smelter's ore→bar) breaks any `IsEmpty()`-based "done" check — this is why `SlotSignatureGate` (baseline-snapshot-then-diff) exists as a distinct gate from `SlotGate`/`NotGate`. Before assuming a new bot's "wait until done" step can reuse `PressAndWaitEmptyPhase`, confirm the crafted/consumed item actually vanishes from the indicator slot rather than just changing appearance in place.
7. **A severe `PixelSearch`/`PixelGetColor` per-call performance cliff on this machine** (~7ms fixed overhead per call, discovered while building AutoFighter) — a full-screen row-by-row scan (even at a coarse stride) can cost seconds, not milliseconds, purely from call count. Fixed by scoping the scanned region tightly around a reference point rather than relying on stride alone. Budget total call count against ~7ms/call for any future full-region scan.
8. **"Stale transient-state signal" needs a real entry-time baseline, not just "seen the other state first."** The combat-indicator's kill-color lingers ~3s after a kill (death animation) — requiring the *start* color to be seen before a kill counts as fresh broke genuine instant kills (weak NPCs with no visible fight ramp-up). Correct fix: snapshot whether the terminal state was already true at phase-entry; only trust it again once it's been observed to leave that baseline at least once. See `ARCHITECTURE.md`'s AutoFighter/AutoFighterLoot/FruitStall section.
9. **A shared phase's timeout guard must be reset on every tick that proves real, ongoing progress — not just once on the transition tick.** `WaitCombatPhase` originally only reset its phase timer the one tick combat-start was first detected; any real fight that ran close to or past `phaseTimeoutCombat` got force-stopped even while the combat indicator was actively confirming it was still in progress. Fixed by resetting unconditionally on every tick `startColor` matches. This kind of "timer reset gated behind a transition-only condition" bug is worth checking for in any other shared phase with a similarly-shaped "still working, just slow" branch.
10. **A shared phase's hardcoded next-phase name breaks for any consumer that doesn't have that phase.** `WaitCombatPhase` originally hardcoded `return "scanAndAttack"` on its retry-timeout path — correct for AutoFighter/AutoFighterLoot, but a hard crash ("Unknown phase") for FruitStall, which has no `scanAndAttack` phase at all. Fixed by adding a `retryNextPhaseName` constructor param that defaults to `killNextPhaseName` (preserving old behavior for existing callers) but lets a differently-shaped bot supply its own. General lesson: a shared phase's every hardcoded phase-name return should be a parameter, not a literal, once more than one bot constructs it.

## Verification methodology used throughout

For every code change: load-check via `AutoHotkey64.exe /ErrorStdOut` (`PowerShell`'s `Start-Process ... -PassThru`, sleep ~1.5s, check `$p.HasExited` — `False` means it loaded cleanly and is idle waiting for F5), then a real F5 trigger in-game, then check the bot's own debug log — never just a read-through. Several real bugs (the Smithing bank-marker color, the Smelter ore→bar empty-check, all three `WaitCombatPhase` bugs found while building FruitStall) were only caught this way, not by static review. **When a change touches `Core/SharedPhases.ahk`, load-check every bot that constructs the touched phase class**, not just the bot you're actively working on — three separate bots (`AutoFighter`, `AutoFighterLoot`, `FruitStall`) currently share `WaitCombatPhase`.

## Prompt for continuing this work in a future session

> Continuing work on this AHK v2 OOP OSRS automation framework. Read `ARCHITECTURE.md` first (primary reference: every shared class, gate, pattern, and gotcha) and `CURRENT_STATE.md` (this file, status snapshot) before starting anything. Each bot also has its own `Bots/<Name>/README.md` — read the relevant one before extending or debugging that specific bot.
>
> Nine bots exist (Motherlode, MotherlodeFixed, Firemaking, Smelter, Smithing, AutoFighter, AutoFighterLoot, Agility, FruitStall), all load-check verified; all but the newest are live-verified in-game across multiple cycles. A cross-bot unification pass consolidated duplicated click/phase code into `Clicker.ClickSettled` and `Core/SharedPhases.ahk` — read that section of `ARCHITECTURE.md` before writing a new bot's phases by hand, since several phase shapes (including the full combat-detection loop, `ScanAndAttackPhase`/`WaitCombatPhase`) are already generic and reusable across 3 bots.
>
> Standing rules: every pause/delay/coordinate/color/threshold is `.ini`-backed, nothing hardcoded in phase code (one sanctioned exception: inventory pixel-grid layout, a fixed client-window property). Every delay routes through `Waiter.After(profile, key)` — never a bare `Sleep`. `Config.Load()` fails fast listing every missing key at once. Verify every change by loading it (`AutoHotkey64.exe /ErrorStdOut`), not just reading the code — and when the change touches a shared file, load-check every bot that uses it, not just the one you're working on.
>
> An `Interfaces/Bank.ahk`-based multi-slot withdraw-plan pattern (`.ini` keys `withdrawSlotCount` + `withdrawSlot<i>Index`/`withdrawSlot<i>Clicks`) is established and reusable for any bot that withdraws from more than one bank slot or needs repeat clicks on one slot.
>
> A full per-bot audit (this session) surfaced several unfixed gaps worth prioritizing before further feature work: Motherlode has no water-wheel-repair handling at all; Firemaking always lights fires at a fixed spot with no relocation logic; Smelter's `SlotSignatureGate.Calibrate()` runs after a settle delay instead of before it; AutoFighterLoot's missed-click retry path is needlessly slow; FruitStall has no explicit empty-check on inventory slot 1 before trusting a fresh steal. See each bot's own README for the full writeup.
