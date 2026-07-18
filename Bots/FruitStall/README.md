# FruitStall

## Overview

Thieving bot: click a fixed fruit stall pixel when it shows a "ready" color, wait
for the stolen fruit to land in inventory slot 1, click that slot to pick it up,
and repeat. Real OSRS thieving carries a per-steal detection chance — when a
steal is detected, no loot lands and an aggressive NPC starts approaching to
retaliate. This bot infers "detected" purely from the absence of loot within a
timeout (there is no separate detection-message read), then hands off to the
same `WaitCombatPhase` class `Bots/AutoFighter/autofighter.ahk` uses to survive
the fight, since the NPC auto-attacks on arrival with no attack click needed.
After a confirmed kill plus a settle delay, it resumes thieving. Two phases
total (`thieving`, `waitCombat`) — the simplest bot in the repo.

- **Start location / setup**: character must already be standing at the stall,
  close enough that `stallX/stallY` is the correct on-screen pixel for the
  stall's ready-indicator and that a click there actually reaches the stall
  (no walking/pathing logic exists in this bot at all).
- **Required calibration**:
  - `stallX`/`stallY` + `stallColor` (`0x00FF00`) — the stall's ready-pixel,
    calibrated per-client-window/per-zoom like every other fixed-pixel check
    in this framework.
  - `combatIndicatorX`/`combatIndicatorY` + `combatStartColor`/`combatKillColor`
    — **reused verbatim from AutoFighter's calibration**, not recalibrated for
    this bot, since both bots read the same underlying HP/combat overlay.
    If AutoFighter's combat indicator position/colors are ever recalibrated,
    check whether this bot's `.ini` needs the same update.
  - The 4x7 inventory grid (`inventoryLayout` in `fruitstall.ahk:161`) is
    hardcoded, not `.ini`-backed — same sanctioned exception as every other
    bot (fixed client-window property, not a gameplay tunable).

## Files

- Entry point: `Bots/FruitStall/fruitstall.ahk`
- Config: `Config/auto-fruitstall.ini`
- Log: `logs/auto-fruitstall-v4-debug.log`

## State Machine

**`thieving` (`ThievingPhase`, bot-specific, `fruitstall.ahk:51-104`)**

1. Window-focus guard (standard pattern, `ARCHITECTURE.md` §Diagnostics).
2. `ColorSearch.IsColorAt(stallX, stallY, stallColor, colorTolerance)` — a
   single-pixel check, **not** a region/block scan (unlike AutoFighter's
   `ScanAndAttackPhase`, which scans a whole box for an irregular blob; this
   bot's stall pixel is a single fixed calibrated point that either matches or
   doesn't). If not ready, sleeps `stallPoll` and returns `"thieving"` (stay).
3. Once ready: logs, `ClickSettled` on the stall pixel, `ResetPhaseTimer` (real
   progress).
4. Enters a **blocking inline loop** (not a tick-by-tick phase re-entry) that
   polls `firstSlotGate.IsSet()` (a `SlotGate(1, colorTolerance, inventory)`)
   every `lootPoll` (200ms) until either:
   - **Loot detected**: `SlotCenter(1, ...)` → `ClickSettled` on slot 1 →
     `ResetPhaseTimer` → sleep `stallPoll` → return `"thieving"` (cycle
     repeats from the top).
   - **Deadline reached** (`A_TickCount >= deadline`, deadline = click time +
     `lootWaitTimeoutMs`, 2000ms): breaks out, logs "assuming detected,
     waiting for combat", returns `"waitCombat"`.

   Note this loop runs inside a single `Run(ctx)` call — it blocks the engine
   tick for up to ~2 seconds (in `lootPollMs`-sized slices) rather than
   yielding back to `Engine.Tick()` between polls. This differs from most
   other phases' "return same name, get ticked again" style, but is
   deliberate here (identical shape to how other phases block inside a
   `loop` for a bounded wait) and matches live-tested behavior.

**`waitCombat` (shared `WaitCombatPhase`, `Core/SharedPhases.ahk:252-349`)**

Constructed at `fruitstall.ahk:176-180`:
```
WaitCombatPhase(combatIndicatorGate, combatStartColor, combatKillColor,
    "combatPoll", retryClickAfterMs, combatStartTimeoutMs,
    "postKillSettle", "thieving", "thieving")
```
`killNextPhaseName = "thieving"` and the 9th arg `retryNextPhaseName =
"thieving"` — both wired to this bot's only other phase, since there is no
`"scanAndAttack"` phase here at all. This is exactly the case the 9th param
was added for this session (see Bugs section).

Per-tick logic (unchanged from AutoFighter's copy, see `ARCHITECTURE.md`
§AutoFighter for the full stale-signal rationale):
1. First tick after entry: snapshot `staleKillCleared = !indicatorGate.Matches(killColor)`.
2. If stale kill-color hasn't cleared yet, only a real transition away from
   `killColor` clears it — prevents an immediate false "kill confirmed" from
   the *previous* fight's ~3s death-animation linger.
3. Once cleared, a genuine `killColor` reading → log, `postKillSettle` delay,
   full scratch reset (`entrySnapshotTaken`, `staleKillCleared`,
   `combatStartLogged`, `combatWaitStartedAt`, `targetWaitStartedAt`),
   `ResetPhaseTimer`, returns `killNextPhaseName` = `"thieving"`.
4. `startColor` match → log once via `combatStartLogged` latch, unconditional
   `ResetPhaseTimer` every tick (long fights don't trip `phaseTimeoutCombat`),
   stays in `"waitCombat"`.
5. Neither color yet: tracks `combatWaitStartedAt`; past
   `combatStartTimeoutMs` (10000ms) → `ctx.engine.Stop(...)`; past
   `retryClickAfterMs` (4000ms) but under the outer ceiling → resets its
   per-attempt scratch state and returns `retryNextPhaseName` = `"thieving"`
   (goes back to re-check the stall/loot state — appropriate here since there
   was never an attack click to "retry"; see Known Risks for what this
   actually means for a passive-aggro bot).

## Config Reference

| Section | Key | Meaning | Current Value | Misconfiguration Impact |
|---|---|---|---|---|
| Settings | `runMode` | Hold Ctrl during clicks (force-attack/force-walk style). 1=on | `0` | If the client requires Ctrl-held clicks for this action and it's left `0`, clicks may resolve differently in-game (e.g. examine/walk instead of intended action). |
| Tunables | `runnerTickMs` | Engine tick interval | `50` | Lower = more responsive/more CPU; too high delays reaction to state changes outside the blocking loot-wait loop. |
| Tunables | `phaseTimeoutThieving` | Outer stall for `thieving` phase with no `ResetPhaseTimer` call | `60000` | Too low: could false-trip mid-legitimate-wait if the stall takes unusually long to become ready. Too high: a truly stuck bot runs longer before failing safe. |
| Tunables | `phaseTimeoutCombat` | Outer stall for `waitCombat` | `60000` | Same tradeoff; must stay comfortably above `combatStartTimeoutMs` (10000) + `postKillSettleDelayMs` (6000) plus real fight duration, or the generic engine timeout could fire mid-fight instead of the phase's own more specific stop reason. |
| Tunables | `colorTolerance` | Shared RGB per-channel tolerance for stall ready-pixel AND `SlotGate` empty-check | `20` | Too low: false negatives from anti-aliasing/lighting flicker (missed ready state, or slot mistakenly read as empty). Too high: false positives (stall read as ready off pure-color coincidences elsewhere in that pixel's neighborhood, or occupied slot misread as empty). |
| Stall | `stallX`/`stallY` | Ready-pixel screen coordinate | `1251`/`683` | Wrong coordinate = never detects ready (stuck polling forever, bounded only by `phaseTimeoutThieving`) or clicks the wrong game element. |
| Stall | `stallColor` | Ready-indicator color | `0x00FF00` | Wrong color = same as above — permanent non-detection. |
| Stall | `stallPollMs` | Poll interval while waiting for ready AND settle delay after a successful loot-slot click before re-checking | `200` | Too low = wasted CPU/PixelSearch calls; too high = slower reaction, and (since it doubles as the post-loot-click settle) a too-low value risks re-checking the stall before the client visually registers the slot-1 click. |
| Loot | `lootWaitTimeoutMs` | Max wait for slot 1 to fill before assuming detection | `2000` | Too short: real (slightly delayed) loot could be missed, causing a false trip to `waitCombat` even though no NPC is coming (wastes `retryClickAfterMs`+`combatStartTimeoutMs` before returning to thieving). Too long: real detections take longer to react to (NPC gets a longer free run-up before the bot even starts watching for combat). |
| Loot | `lootPollMs` | Poll interval inside the loot-wait loop | `200` | Too low = tight busy loop of PixelGetColor calls (still cheap, single pixel checks via `SlotGate`, not a full scan); too high = coarser granularity against the 2000ms deadline. |
| Combat | `combatIndicatorX`/`Y`, `combatIndicatorTolerance` | Combat HP/status pixel, reused from AutoFighter | `2135`/`1265`/`20` | Wrong coordinate/tolerance = `waitCombat` never sees start or kill signal → always runs out the clock to `combatStartTimeoutMs` and stops the engine on every single detected-theft event. |
| Combat | `combatStartColor` | "Fighting" color | `0x078A36` (green) | Wrong value = `combatStartLogged`/timer-reset path never fires; long fights would then incorrectly trip `phaseTimeoutCombat` mid-fight since progress is never re-recognized. |
| Combat | `combatKillColor` | "Kill confirmed" color | `0x631413` (dark red) | Wrong value = kill never recognized → runs to `combatStartTimeoutMs`, stops engine after every single fight, even successful ones. |
| Combat | `combatPollMs` | Poll interval in `waitCombat` | `200` | Same tradeoff as other poll intervals. |
| Combat | `retryClickAfterMs` | No-signal-yet threshold before returning to `thieving` (retry path) | `4000` | For this bot specifically: this is the window in which the bot assumes "NPC hasn't reached/engaged yet." Too short = bounces back to `thieving` (and re-clicks the stall) while the NPC is still walking up, potentially re-triggering another theft attempt or a wasted stall click mid-approach. Too long = slower recovery if the "detection" was actually a false read (no NPC coming at all) — see Known Risks. |
| Combat | `combatStartTimeoutMs` | Outer ceiling regardless of retries | `10000` | Too low relative to real NPC travel time = bot gives up and fully stops even though the NPC was legitimately still approaching. |
| Combat | `postKillSettleDelayMs` | Delay after confirmed kill before resuming `thieving` | `6000` | Too short = returns to the stall while kill animation/loot-drop/aggro-reset from the just-killed NPC is still resolving on screen, risking a misread of any shared pixels. Too long = wasted idle time every kill cycle. |
| ClickExecution | `clickSettleMs`, `clickSettleJitterPercent`, `ctrlHoldSettleMs` | Standard click-execution timing (see `ARCHITECTURE.md` §Actions) | `200`/`0`/`100` | Same as every other bot — `clickSettleJitterPercent=0` means no jitter regardless of `Humanizer.enabled` (see Anti-Ban section). |

## Known Risks & Edge Cases

- **Stale/leftover slot-1 contents causing false-positive instant "loot detected."**
  → **Current behavior**: `ThievingPhase` clicks the stall, then immediately
  begins polling `firstSlotGate.IsSet()` with no explicit "confirm slot 1 is
  actually empty first" step. The design assumes slot 1 was just emptied by
  the *previous* cycle's own successful slot-1 click (see the code's own
  cycle order: click stall → wait for slot 1 → click slot 1 → click stall
  again → wait for slot 1...). This holds as long as every slot-1 click
  actually clears the slot.
  → **Risk/impact**: if a slot-1 click ever fails to register (client lag,
  focus loss between click and confirmation, or — see next item — inventory
  full so the click is a no-op), the *next* cycle's `IsSet()` check reads
  true on the very first tick, before any real loot has landed. The bot logs
  "loot detected," re-clicks slot 1 (likely another no-op for the same
  reason), and returns to `"thieving"` having never actually waited the real
  `lootWaitTimeoutMs`. This can repeat indefinitely: the bot appears to be
  working (fast, clean cycles) while never truly confirming fresh loot, and
  critically, a REAL detected-theft event during this window would be masked
  — the bot would still report "loot detected" from stale slot-1 content
  instead of correctly falling through to `waitCombat`, so it would not react
  to an inbound aggressive NPC at all until the NPC's own attack interrupts
  some other check.

- **Full inventory (28/28) causing the same false-positive, systematically.**
  → **Current behavior**: no `IsFull()` check exists anywhere in this bot —
  `Inventory` is constructed with no full/empty/sack gates at all
  (`fruitstall.ahk:162`, only `firstSlotGate` is built standalone). If the
  inventory fills up, any click on slot 1 is a guaranteed no-op (nowhere for
  an item to go, and if slot 1 itself already holds an item from earlier that
  never got collected, `SlotGate(1)` is permanently "occupied").
  → **Risk/impact**: once inventory is full, every subsequent cycle
  instantly reports "loot detected" (slot 1 was never empty to begin with),
  clicks it (no-op), and loops back to click the stall again — a fast,
  seemingly-healthy-looking loop that is actually not thieving anything new
  and, per the above, would fail to notice a real detection/combat event
  during this state. There is no inventory-full detection or stop condition
  in this bot at all.

- **Multiple NPCs from one detected steal.** In real OSRS thieving, a single
  failed steal attempt spawns exactly one aggressive NPC retaliation (not
  multiple) for stalls of this type. The bot's design (one `PixelColorGate`
  read, one kill-confirmation) matches this — it does not need to handle
  concurrent multi-NPC combat. Not a bug, just confirming the 1:1 assumption
  holds for this content.

- **Stale-kill-color guard with no attack click.** The guard (`staleKillCleared`)
  was originally designed around AutoFighter's shape (attack click just
  fired, so "was killColor already true at entry" cleanly means "leftover
  from the fight before this one"). FruitStall enters `waitCombat` with **no**
  click of its own — entry is triggered purely by the loot-timeout in
  `ThievingPhase`. This still works correctly: the snapshot question ("is
  killColor showing right now, at the moment we started caring") is
  meaningful regardless of whether a click preceded it — it's still
  distinguishing "leftover from a previous kill that hasn't visually cleared
  yet" from "this fight's own outcome." No regression from the no-click shape;
  the guard's logic doesn't actually depend on a click having just happened,
  only on time having passed since the *previous* transition into
  `waitCombat`. Worth double-checking live if theft attempts can occur in
  rapid succession right after a kill — `postKillSettleDelayMs` (6000ms) is
  the only buffer ensuring the kill-color has visually cleared before the
  next `waitCombat` entry's snapshot is taken.

- **Window focus lost mid-cycle.** Guarded at the top of `ThievingPhase.Run`
  (returns `"thieving"` without acting) — but note the blocking loot-wait
  loop (step 4 in State Machine) does **not** re-check focus once entered;
  if focus is lost mid-loop, the loop still runs to completion (harmless,
  since it's just polling pixels, not clicking) and only the *next* `Run`
  call re-checks focus before any new click. `WaitCombatPhase.Run` has no
  focus guard at all (confirmed: `Core/SharedPhases.ahk:277` starts straight
  into the snapshot logic) — this is inherited from AutoFighter's original
  version and is a pre-existing gap in the shared class, not something new
  to this bot.

- **Stall pixel never becoming ready (stuck loop).** Bounded by
  `phaseTimeoutThieving` (60000ms) via the engine's generic `FailSafe`
  tripwire (`ResetPhaseTimer` is only called on real progress — a stall
  click or a slot-1 click — never merely for polling), so a permanently
  not-ready stall does eventually stop the engine. No dedicated inner
  wait-timeout/log exists for this specific condition the way `waitCombat`
  has its own `combatStartTimeoutMs` — the only signal is the generic engine
  "Phase 'thieving' timed out" log line.

- **Combat starting but never confirming a kill.** Covered by
  `combatStartTimeoutMs` (10000ms) as an outer ceiling regardless of retries
  — confirmed still in effect for this no-click bot (line 332's check is
  unconditional on how `waitCombat` was entered).

## Anti-Ban / Human-Like Behavior Notes

- `Humanizer` is constructed with `enabled=false` (`fruitstall.ahk:150`),
  matching every other bot in the repo — `Offset`/`Jitter` are no-ops.
  `clickSettleJitterPercent=0` in the `.ini` currently does nothing either
  way, but the plumbing is left in place per the framework's standing
  convention (`ARCHITECTURE.md` §Config) rather than stripped.
- All poll intervals (`stallPollMs`, `lootPollMs`, `combatPollMs`) are fixed,
  not randomized — every wait is `baseMs` with zero jitter applied in
  practice.
- `runMode` (Ctrl-hold) is off (`0`) — clicks are plain left-clicks, no
  Ctrl modifier.
- Net effect: this bot's on-screen behavior is currently fully
  deterministic/rhythmic (fixed-interval polling, zero click jitter) — no
  human-like timing variance is actually active, only scaffolded.

## Bugs Found This Audit

No new bugs found in the reviewed code paths beyond the pre-existing,
documented risks above (stale slot-1 / full-inventory false-positive, no
focus guard in `WaitCombatPhase`, no dedicated inner stall-timeout log) —
none of these are regressions, they're either inherited from the shared
class or genuinely new gaps specific to this bot's simpler design (no
`IsFull()`/`IsEmpty()` gates at all).

**Confirmation of the 3 previously-fixed `WaitCombatPhase` bugs** (all
verified present in the current `Core/SharedPhases.ahk`, read fresh this
audit):

1. **Hardcoded `"scanAndAttack"` next-phase-name — FIXED.** `WaitCombatPhase.__New`
   (`Core/SharedPhases.ahk:253`) takes a 9th parameter `retryNextPhaseName :=
   ""`, defaulting to `killNextPhaseName` when omitted (line 270) so
   AutoFighter's existing call sites are unaffected. FruitStall passes
   `"thieving"` explicitly for both the 8th (`killNextPhaseName`) and 9th
   (`retryNextPhaseName`) args (`fruitstall.ahk:176-180`). The retry path
   (line 343) returns `this._retryNextPhaseName`, not a literal string — if
   this fix had NOT been present, FruitStall would crash (or silently try to
   jump to a non-existent `"scanAndAttack"` phase, which `Engine.Tick` would
   catch as `"Unknown phase"` and stop the engine) the first time a theft
   attempt went undetected long enough to hit the retry path.
2. **Missing "combat started" log — FIXED.** `combatStartLogged` latch present
   (`Core/SharedPhases.ahk:311-314`), logged once per fight independent of
   `combatWaitStartedAt`. Without this, there'd be no log line at all marking
   when a fight actually begins — only the eventual kill-confirmed or
   timeout lines — making live debugging of fight timing much harder.
3. **Phase-timeout false positive on long fights — FIXED.** The
   `ctx.failsafe.ResetPhaseTimer(ctx)` call inside the `startColor` match
   branch (line 320) is unconditional — it fires on every tick `startColor`
   still matches, not gated behind the `combatStartLogged` first-time check.
   If this had regressed to "only reset once," a fight lasting longer than
   `phaseTimeoutCombat` (60000ms) would falsely trip the engine's generic
   phase-timeout mid-fight even though the bot was actively and correctly
   waiting on a real, ongoing fight.

## Future Agent Development Roadmap

- **Add a pre-cycle "slot 1 is actually empty" check before trusting
  `SlotGate` again.** After clicking the stall (before starting the loot-wait
  loop), verify `!firstSlotGate.IsSet()` first (or wait briefly for it to
  clear) rather than assuming the previous cycle's click already cleared it.
  This directly closes the stale-slot-1 false-positive risk documented above.
- **Add an `IsFull()` gate and a stop/alert condition for full inventory.**
  Currently there's no full-inventory detection at all; a bot silently
  looping on a full inventory (never truly thieving, never reacting to real
  detections) is a hard-to-notice failure mode. Consider a gate on slot 28
  (or the last slot in reading order) similar to Motherlode's `AndGate`
  full-check, wired to `ctx.engine.Stop(...)` or a bank-trip phase if one is
  ever added.
  **Note:** RuneLite's default AHK-visible client typically shows a "your
  inventory is too full" chat message rather than blocking the click
  silently — if a message-region OCR/color check is ever added elsewhere in
  this framework, that would be a stronger signal than inferring fullness
  from slot 28 alone, since thieving loot can land in any empty slot, not
  just append at a fixed position.
- **Consider adding a focus guard to the shared `WaitCombatPhase.Run`.**
  It's currently the one phase shape in the shared library without the
  standard first-line focus check (inherited gap from AutoFighter). Low risk
  since this phase never clicks, but worth aligning with the rest of the
  framework's convention for consistency/future-proofing if a variant of
  this phase ever needs to click (e.g. a bot that must manually attack back).
- **Tune `postKillSettleDelayMs` (currently 6000ms) against live NPC
  respawn/despawn timing** once more real thieving-retaliation cycles have
  been observed — confirm 6s is enough for the kill animation and any
  loot-drop from the killed NPC to fully clear before the bot re-approaches
  the stall, but not so long that it wastes idle time every detected-theft
  cycle.
- **Tune `lootWaitTimeoutMs` (2000ms) against the real steal-success animation
  delay** live — if genuine successful steals occasionally take longer than
  2s to land fruit in slot 1 (network/client lag), this bot would misfire
  into `waitCombat` on a false detection reading, then correctly fail to find
  a combat signal and burn `retryClickAfterMs` + return to thieving anyway —
  self-correcting, but worth confirming this doesn't happen often in
  practice, since each false trip adds a few extra seconds of dead time.
- **Consider a dedicated inner timeout/log for "stall pixel never ready"**
  distinct from the generic engine phase-timeout message, matching the
  pattern `WaitCombatPhase` and `ScanAndAttackPhase` use (their own
  `xWaitStartedAt` + specific log line before calling `ctx.engine.Stop`) —
  currently this condition is only caught by the generic `FailSafe` tripwire
  with a generic "Phase 'thieving' timed out" message, giving less specific
  diagnostic information than other bots' equivalent stuck-detection cases.
