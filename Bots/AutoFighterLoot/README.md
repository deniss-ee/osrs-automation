# AutoFighterLoot

## Overview
AutoFighterLoot fights the same kind of NPCs as plain AutoFighter (scans for an
irregular magenta (`0xFF00FF`) NPC-overlay outline near the player, clicks it,
waits for the OSRS combat/HP indicator to confirm a kill) but adds a **loot
pickup step after every kill**: right-click the dropped item's ground text
("bb-item.png"), left-click the "Take" context-menu option ("take-bb.png"),
then click inventory slot 1 to consume/use whatever landed there. It is built
for a specific single-drop grinding loop (kill one NPC type, pick up exactly
one recognizable ground item, put it in slot 1) rather than general loot
collection.

- **Start location / setup assumptions**: player standing at a fixed spot
  next to a pen/area of attackable NPCs, same as AutoFighter. RuneLite window
  must be focused (`WindowFocus` gate) for any click to fire. Inventory slot 1
  is assumed to be empty/available every cycle — there is no full-inventory
  check anywhere in this bot (see Known Risks).
- **Required calibration** (must be re-measured if resolution/client layout
  or NPC/indicator visuals change):
  - `refPointX/Y`, `targetSearchRadiusX/Y`, `targetColor`/tolerance — same
    scan-region calibration as AutoFighter.
  - `combatIndicatorX/Y`, `combatStartColor`, `combatKillColor` — the same
    1x1 HP/combat-indicator pixel AutoFighter uses.
  - `lootSearchCenterX/Y`, `lootSearchWidth/Height` — the region
    `bb-item.png`/`take-bb.png` are searched in (currently centered near the
    player and sized to effectively the whole 2560x1440 screen).
  - `Images/bb-item.png` (94x22, `*Trans0x00FF00` transparency key) and
    `Images/take-bb.png` (194x30, no transparency key) — both must be
    re-captured if the ground-item text style, context-menu font, UI scale,
    or client resolution changes. `ImageAnchor` is told the pixel dimensions
    by the caller (AHK can't self-measure a PNG), so a re-captured image of a
    different size also requires updating the `94, 22` / `194, 30` args in
    `autofighter-loot.ahk`.
  - Inventory layout (`firstX/firstY/cols/rows/slotW/slotH/gapX/gapY`,
    hardcoded in the wiring section, not `.ini`-backed) — the one sanctioned
    non-.ini hardcode per `ARCHITECTURE.md`; only used here for
    `SlotCenter(1, ...)` math, no full/empty gate is attached.

## Files
- Entry point: `Bots/AutoFighterLoot/autofighter-loot.ahk`
- Config: `Config/auto-fighter-loot.ini`
- Log: `logs/auto-fighter-loot-v4-debug.log`
- Images: `Images/bb-item.png`, `Images/take-bb.png`

## How this differs from plain AutoFighter
Plain AutoFighter (`Bots/AutoFighter/autofighter.ahk`) is a 2-phase loop:
`scanAndAttack -> waitCombat -> scanAndAttack` — nothing happens after a kill
except a settle delay before rescanning. AutoFighterLoot reuses the exact
same `ScanAndAttackPhase`/`WaitCombatPhase` classes (both now live in
`Core/SharedPhases.ahk`, not duplicated per-bot) and adds a **third phase,
`lootPickup`**, bolted onto `WaitCombatPhase`'s kill exit:

- `ScanAndAttackPhase` and `WaitCombatPhase` are used completely unmodified
  — same targeting math, same stale-kill-color guard, same retry-on-missed-
  click behavior. Nothing about targeting or combat-detection differs
  between the two bots.
- The only wiring difference: AutoFighter constructs `WaitCombatPhase` with
  `killNextPhaseName` defaulted to `"scanAndAttack"` (its own default, since
  it doesn't pass a 9th arg); AutoFighterLoot explicitly passes
  `"lootPickup"` as the 9th positional arg (`killNextPhaseName`), so a
  confirmed kill routes into the new loot phase instead of straight back to
  scanning.
- Confirmed: AutoFighterLoot's `WaitCombatPhase` construction (autofighter-loot.ahk:243-246)
  passes exactly 9 positional args (`indicatorGate, startColor, killColor,
  combatPollKey, retryClickAfterMs, startTimeoutMs, postKillSettleKey,
  "lootPickup"`) — it does **not** pass a 10th arg for
  `retryNextPhaseName`. Per `Core/SharedPhases.ahk:270`, the constructor's
  default (`retryNextPhaseName != "" ? retryNextPhaseName : killNextPhaseName`)
  makes a missed-click retry fall back to `killNextPhaseName`, i.e.
  `"lootPickup"` — **not** `"scanAndAttack"`. This means: if the attack click
  missed the target (no combat signal within `retryClickAfterMs`), the retry
  path sends this bot into `lootPickup`, not back to re-scanning for a
  target. This is intentional/expected per the recent shared-phase fix (the
  fallback exists specifically so bots that don't pass a 10th arg keep their
  old hardcoded-target behavior) — but for THIS bot that old hardcoded
  behavior was `"scanAndAttack"` (AutoFighter's own retry target), not
  `"lootPickup"`. In practice this is likely harmless: `lootPickup`'s stage 0
  is a single settle delay then an image search for `bb-item.png`, which
  will simply time out (10s, `bbItemWaitTimeoutMs`) and gracefully fall back
  to `scanAndAttack` anyway (see `_ResetAndReturnToScan`) since no loot
  exists after a missed click. But it does mean a missed-click retry burns a
  wasted `postKillLootDelayMs` (3300ms) + up to `bbItemWaitTimeoutMs` (10s)
  before actually re-scanning, instead of retrying the scan immediately.
  Document, don't fix, per audit instructions — but flag for a future agent.
- Loot pickup is **not** triggered by an inventory-slot-change gate or a
  ground-item color scan — it's a fixed 3-stage internal state machine
  inside one `Phase` (`LootPickupPhase`, mirroring Motherlode's
  `ReturnMine2Phase` multi-stage-in-one-phase pattern), driven entirely by
  two image searches (`bb-item.png`, `take-bb.png`) plus a final
  unconditional click on inventory slot 1. There's no verification step that
  slot 1 actually received an item — the phase clicks blind and returns to
  scanning either way.

## State Machine
Three phases: `scanAndAttack -> waitCombat -> lootPickup -> scanAndAttack`.

- **`scanAndAttack`** (shared `ScanAndAttackPhase` from `Core/SharedPhases.ahk`,
  constructed at autofighter-loot.ahk:235-241): scans a box around
  `(refPointX, refPointY)` ± `targetSearchRadiusX/Y` for the nearest
  `targetColor` blob via `ColorSearch.FindNearestBlobCenter`, clicks its
  centroid (Ctrl-held if `runMode=1`), then unconditionally transitions to
  `waitCombat`. Resets `entrySnapshotTaken`/`combatWaitStartedAt` on every
  click (fresh baseline for `WaitCombatPhase`'s stale-kill guard). On
  repeated no-match for `targetWaitTimeoutMs` (30s), calls
  `ctx.engine.Stop(...)` and stays in `scanAndAttack` (engine is stopped, so
  this is moot).
- **`waitCombat`** (shared `WaitCombatPhase`, constructed at
  autofighter-loot.ahk:243-246, `killNextPhaseName="lootPickup"`,
  `retryNextPhaseName` unset → defaults to `"lootPickup"` — see differences
  section above): polls the combat-indicator pixel. Fresh kill (killColor,
  past the stale-baseline guard) → settle (`postKillSettle`) → **`lootPickup`**
  (not `scanAndAttack` as in plain AutoFighter). Combat-start color seen →
  stays in `waitCombat`, resets the phase timer every tick (long-fight-safe,
  see Bugs section). No signal for `retryClickAfterMs` (2600ms per this
  bot's `.ini`, shorter than AutoFighter's 4000ms) → returns
  `retryNextPhaseName`, which is `"lootPickup"` (see above). No signal at
  all for `combatStartTimeoutMs` (10s) → `ctx.engine.Stop(...)`.
- **`lootPickup`** (bot-specific `LootPickupPhase`, this file, lines 54-153):
  internally staged 0-3 via `ctx.Get("lootStage", 0)`:
  - **Stage 0**: one-time settle delay (`postKillLootDelay` =
    `postKillLootDelayMs`, 3300ms) to let the death animation/ground-item
    drop settle, then advances to stage 1 unconditionally (same tick sets
    stage to 1 and returns `"lootPickup"` — costs one extra engine tick, not
    a real delay).
  - **Stage 1**: searches for `bb-item.png` (ground-item text) in
    `lootRegion`. Found → right-click it (never Ctrl-held, regardless of
    `runMode` — hardcoded `false` for the runMode arg on this specific
    click, autofighter-loot.ahk:107, since Ctrl+right-click's effect on an
    OSRS context menu is untested), advance to stage 2. Not found → poll
    every `bbItemPoll` (100ms) up to `bbItemWaitTimeoutMs` (10s), then give
    up gracefully (log + `_ResetAndReturnToScan` → `"scanAndAttack"`, no
    `ctx.engine.Stop`).
  - **Stage 2**: searches for `take-bb.png` (the context-menu "Take" option
    itself — no separate menu-position math, the image anchor's own
    position is the click target). Found → `ClickSettled` (runMode-aware
    this time), advance to stage 3. Not found → poll every `takeBbPoll`
    (100ms) up to `takeBbWaitTimeoutMs` (10s), then same graceful give-up.
  - **Stage 3** (implicit "else" — no `stage == 3` guard, see Bugs): settle
    (`postTakeDelay`, 1400ms), click inventory slot 1 via
    `ctx.inventory.SlotCenter(1, ...)`, then unconditionally
    `_ResetAndReturnToScan` → `"scanAndAttack"`, resetting `lootStage`,
    `lootPreDelayApplied`, `lootWaitStartedAt` to their initial values.
  - Deliberate exception to the framework's usual timeout convention: a
    stage-1/stage-2 image-search timeout in this phase does **not** call
    `ctx.engine.Stop` — it logs a miss and resumes scanning, since a single
    missed loot pickup is not treated as fatal (comment at
    autofighter-loot.ahk:48-52). `phaseTimeoutLoot` (60s) remains as an
    outer engine-level safety net in case the phase truly hangs (e.g.
    lost focus for the whole duration).

## Config Reference
All keys in `Config/auto-fighter-loot.ini`, section `[Tunables]` unless noted.

| Key | Meaning | Current value | If misconfigured |
|---|---|---|---|
| `runnerTickMs` | Engine tick interval | 50 | Too low = wasted CPU; too high = laggy phase reactions |
| `phaseTimeoutScan` | Outer timeout for `scanAndAttack` | 60000 | Bot stops if no target found this long |
| `phaseTimeoutCombat` | Outer timeout for `waitCombat` | 60000 | Bot stops if combat makes no progress this long |
| `phaseTimeoutLoot` | Outer timeout for `lootPickup` | 60000 | True "nothing happening at all" net — the phase's own internal image-search timeouts (10s each) fire first and recover gracefully; this only matters if e.g. focus is lost for the whole loot sequence |
| `targetColor` | NPC-overlay outline color | 0xFF00FF | Wrong value = scan never finds anything, bot stops after `targetWaitTimeoutMs` |
| `targetColorTolerance` | RGB tolerance for target match | 20 | Too tight = misses valid NPCs; too loose = false positives on similar-colored UI |
| `targetBlobRadius` | Centroid-scan box half-size around seed pixel | 33 | Too small = centroid biased toward blob edge, mis-clicks; too large = drifts onto neighboring NPC |
| `targetSampleRate` | Row stride for centroid scan | 10 | Too coarse = imprecise centroid; too fine = slower scan |
| `targetSeedRowStep` | Row stride for seed search | 10 | Same trade-off as above, for the seed phase |
| `refPointX`/`refPointY` | Reference point ("character center") for nearest-blob search | 1049 / 502 | Wrong value = picks wrong/no NPC, or search region misses the pen entirely |
| `targetSearchRadiusX`/`Y` | Half-width/height of scan box around ref point | 500 / 500 | Too small = misses NPCs at pen edges; too large = slower scan, more false candidates |
| `scanPollMs` | Poll interval while no target found | 100 | Lower = faster re-scan, more CPU |
| `targetWaitTimeoutMs` | Max wait for a target before stopping | 30000 | Too short = false stop during a lull; too long = bot idles a long time before giving up |
| `combatIndicatorX`/`Y` | Combat/HP indicator pixel location | 2135 / 1265 | Wrong coords = never detects start/kill, times out every fight |
| `combatIndicatorTolerance` | RGB tolerance for indicator match | 20 | Too tight = misses due to anti-aliasing; too loose = confuses start/kill colors |
| `combatStartColor` | Indicator color while fighting | 0x078A36 (green) | Wrong = "combat started" log/reset never fires, relies solely on retry/timeout paths |
| `combatKillColor` | Indicator color on kill | 0x631413 (dark red) | Wrong = kills never detected, always times out to `ctx.engine.Stop` |
| `combatPollMs` | Poll interval during combat wait | 100 | Lower = more responsive kill detection, more CPU |
| `retryClickAfterMs` | No-signal-yet threshold before retrying scan+click | 2600 | Too short = interrupts genuine slow-starting fights; too long = wastes time on a truly missed click. **Note: shorter than plain AutoFighter's 4000ms** — see Known Risks |
| `combatStartTimeoutMs` | Outer ceiling for combat signal | 10000 | Must exceed `retryClickAfterMs` or the retry path never gets a chance to run |
| `postKillSettleDelayMs` | Settle delay after confirmed kill, before `lootPickup` | 100 | Too short = risk of racing the death animation into stage 0's own delay (minor, since stage 0 also delays) |
| `postKillLootDelayMs` | Stage-0 delay before searching for the dropped item | 3300 | Too short = `bb-item.png` search starts before the item/ground-text actually renders, wasting stage-1 poll cycles or missing it if `bbItemWaitTimeoutMs` is also tight |
| `lootSearchCenterX`/`Y` | Center of the loot search region | 1249 / 702 | Wrong = never finds `bb-item.png`/`take-bb.png`, always times out to `scanAndAttack` (non-fatal but every kill wastes ~13s of loot attempts) |
| `lootSearchWidth`/`Height` | Loot search region size | 2560 / 1440 | Currently ~full-screen — generous but costs scan time; shrinking it risks missing the item if ground text can appear anywhere in the viewport |
| `bbItemPollMs` | Poll interval, stage 1 | 100 | Lower = faster detection, more CPU |
| `bbItemWaitTimeoutMs` | Max wait for `bb-item.png`, stage 1 | 10000 | Too short = false misses on lag; too long = wastes time when the item genuinely never drops |
| `takeBbPollMs` | Poll interval, stage 2 | 100 | Same trade-off as `bbItemPollMs` |
| `takeBbWaitTimeoutMs` | Max wait for `take-bb.png`, stage 2 | 10000 | Same trade-off as `bbItemWaitTimeoutMs` |
| `postTakeDelayMs` | Settle delay before clicking inventory slot 1 | 1400 | Too short = clicks slot 1 before the taken item actually lands there |
| `clickSettleMs` | Delay between mouse-move and click | 100 | Too short = click may fire before client registers hover |
| `clickSettleJitterPercent` | +/- jitter on click settle delays | 0 | No-op currently since `Humanizer(false)` — see Anti-Ban section |
| `ctrlHoldSettleMs` | Delay after Ctrl-down before release (runMode) | 100 | Too short = force-run modifier may not register |
| `runMode` (`[Settings]`) | Hold Ctrl during clicks (OSRS force-run) | 1 | Applies to scan-click and stage-2/stage-3 clicks; explicitly NOT applied to the stage-1 right-click (hardcoded `false`) |

## Known Risks & Edge Cases

- **No inventory-full handling at all.** **Scenario**: inventory is full when
  loot would land in slot 1 (or slot 1 specifically already holds an
  unstackable item different from the loot). **Current behavior**: stage 3
  clicks slot 1's coordinates regardless — if the slot already holds a
  full/blocking stack, the click is either a no-op or clicks whatever
  already occupies that slot (e.g. re-triggering a "drink/eat" action on an
  unrelated item). There is no `Inventory` full/empty gate wired
  (`ctx.inventory` in this bot has no `fullGate`/`emptyGate`/`sackGate`
  attached — only `SlotCenter` is used). **Risk**: silent failure to loot,
  or an unintended click action on slot 1's existing contents, with no log
  signal distinguishing "worked" from "didn't."
- **No verification that the loot pickup actually succeeded.** **Scenario**:
  `take-bb.png` is clicked but the client is lagging, or the "Take" option
  closed before the click landed. **Current behavior**: stage 3 proceeds
  unconditionally to settle + click slot 1 with no check that a new item
  appeared. **Risk**: bot loops back to combat having missed loot with no
  retry and no log distinguishing success from failure — only a "Clicking
  inventory slot 1" log line either way.
- **Instant-kill NPCs (dying before the fighting-color indicator ever
  renders) combined with a lingering stale kill-color from the previous
  kill.** **Scenario**: a weak NPC dies in one hit right after the loot
  phase completes and scanning resumes, with the previous kill's death
  animation/indicator color still fading. **Current behavior**:
  `WaitCombatPhase`'s stale-kill guard is designed to
  handle exactly this via the entry-snapshot/`staleKillCleared` mechanism
  (see `Core/SharedPhases.ahk:277-303`) — confirmed present and correctly
  carried over into this bot (shared code, unmodified). **Risk**: none
  beyond what already applies to AutoFighter itself; noted here only to
  confirm the fix is inherited correctly.
- **Long-fight phase-timeout reset — confirmed present.** `waitCombat`'s
  `startColor` branch calls `ctx.failsafe.ResetPhaseTimer(ctx)`
  unconditionally on every tick the fighting-color is observed (`Core/SharedPhases.ahk:320`,
  inside the `if (this._indicatorGate.Matches(this._startColor))` block, not
  gated behind a "first observation" flag). This is the fix for the
  previously-live bug where a long fight against a high-HP NPC could exceed
  `phaseTimeoutCombat` (60000ms) mid-fight and force-stop the engine even
  though the fight was actively progressing. Confirmed correctly present in
  the shared code this bot uses.
- **"Combat started" log line — confirmed present.** `combatStartLogged`
  latch (`Core/SharedPhases.ahk:311-314`) logs "Combat started. Waiting for
  kill." exactly once per fight, including on the very first tick if
  `startColor` is already showing (not gated behind the
  `combatWaitStartedAt` timeout arm). Confirmed present, so this bot's logs
  will show combat starts, not just kills.
- **`retryNextPhaseName` fallback → `"lootPickup"`, not `"scanAndAttack"`.**
  As detailed in the "How this differs" section: a missed attack click
  (no combat signal within `retryClickAfterMs`=2600ms) routes into
  `lootPickup` instead of directly back to `scanAndAttack`. Likely
  low-impact in practice (loot phase gracefully times out and falls back to
  `scanAndAttack` after up to ~13 wasted seconds:
  `postKillLootDelayMs` 3300 + `bbItemWaitTimeoutMs` 10000), but it is an
  extra ~13s stall per missed click that plain AutoFighter doesn't pay
  (AutoFighter's own retry goes straight back to `scanAndAttack`). Worth
  passing an explicit 10th arg (`"scanAndAttack"`) if this stall proves
  costly in practice — not changed in this audit per instructions.
- **`retryClickAfterMs` is shorter here (2600ms) than in plain AutoFighter
  (4000ms)**, despite both bots sharing the exact same
  `WaitCombatPhase`/stale-kill-color mechanics and presumably the same
  ~3-second death-animation linger measured for AutoFighter. **Risk**: if
  this bot's kill-color also lingers close to 3s, a 2600ms
  `retryClickAfterMs` leaves comparatively little margin before a
  still-resolving real fight gets misclassified as a missed click and
  retried — worth re-verifying live whether 2600ms is intentional/tuned for
  this specific NPC or simply copy-paste drift from a different (faster)
  target.
- **No re-check of window focus between stage transitions within one tick.**
  Each `Run(ctx)` call re-checks focus at entry, but a stage's own
  `Find`/`ClickSettled` call happens synchronously within that same tick —
  if focus is lost mid-`Run` (rare, but possible via external interruption),
  a click could still fire once. This is the same limitation every phase in
  the framework has (not specific to this bot).
- **Stage-3 "else" has no explicit guard.** `Run(ctx)` falls through to
  stage 3's code whenever `stage` isn't 0, 1, or 2 — including any
  unexpected/corrupted value. Benign today (nothing else ever sets
  `lootStage` to anything but 0-3), but a future edit that adds a stage 4
  without updating this fallthrough would silently misbehave. See Bugs.
- **Loot search region is nearly full-screen** (`lootSearchWidth/Height` =
  2560x1440). `ImageSearch` calls are comparatively cheaper than the raw
  `PixelSearch`/`PixelGetColor` calls that hit the ~7ms/call cliff described
  in `ARCHITECTURE.md`, but a full-screen `ImageSearch` per poll tick (every
  100ms while waiting) is still more expensive than a tightly-scoped region
  would be — no correctness bug, just a latency/CPU cost worth narrowing if
  the ground-item text reliably appears in a smaller, predictable area near
  the player.

## Anti-Ban / Human-Like Behavior Notes
Identical situation to AutoFighter and every other bot in this framework:
`Humanizer(false)` is constructed at autofighter-loot.ahk:216 — humanization
is a deliberate no-op. `Offset()` returns `(0,0)` (no spatial click jitter)
and `Jitter(baseMs, jitterPercent)` returns `baseMs` unchanged (no temporal
jitter), so `clickSettleJitterPercent=0` in the `.ini` currently does
nothing regardless of its value. All poll/settle intervals
(`scanPollMs`, `combatPollMs`, `bbItemPollMs`, `takeBbPollMs`, etc.) are
fixed, not randomized. Per `ARCHITECTURE.md`'s Config section, this is a
known, deliberate, repo-wide choice (the option to fully remove the
humanizer plumbing was considered and explicitly rejected) — don't strip it,
but don't expect it to do anything today either.

## Bugs Found This Audit
No new correctness bugs beyond documented, already-fixed shared-phase issues
(confirmed present and correct in this bot, see above). Two design
observations worth flagging to a future maintainer, neither a crash/hang:

1. **`WaitCombatPhase`'s `retryNextPhaseName` fallback lands on `"lootPickup"`
   instead of `"scanAndAttack"` for this bot** (autofighter-loot.ahk:243-246;
   fallback logic at `Core/SharedPhases.ahk:270`). A missed attack click
   causes an extra ~13s round-trip through `lootPickup`'s own timeout chain
   before the bot actually resumes scanning, instead of retrying immediately.
   Not a hang, not silent data loss — just slower recovery from a missed
   click than plain AutoFighter has. Fix (if ever done): pass
   `"scanAndAttack"` as the 10th positional arg.
2. **No verification anywhere that the loot pickup actually put an item in
   slot 1** — stage 3 clicks blind and always returns to `scanAndAttack`
   regardless of outcome. Combined with no inventory-full gate, a full
   inventory or a failed take-click is indistinguishable from a successful
   one in the log (`"LootPickupPhase: Clicking inventory slot 1"` is logged
   either way). Not a bug in the sense of incorrect code — the phase does
   exactly what its design says — but a coverage gap for a future agent
   asked to make loot pickup more reliable/observable.

## Future Agent Development Roadmap
- **Pass an explicit `retryNextPhaseName="scanAndAttack"` 10th arg** to
  `WaitCombatPhase`'s constructor (autofighter-loot.ahk:243-246) if the
  ~13s missed-click stall through `lootPickup` proves to matter live —
  low-risk, purely additive change (the shared class already supports it).
- **Add a `SlotGate`-based check on inventory slot 1 (or a full-inventory
  gate)** before/after stage 3's click, so a full inventory or a failed
  take can be logged distinctly rather than silently no-op'ing. This would
  need a `fullGate`/`emptyGate` wired onto `ctx.inventory` (currently
  unattached — only `SlotCenter` is used) plus a decision on what to do when
  full (skip loot? stop the bot? bank?) — currently entirely unhandled.
  This is the single highest-value follow-up given how central "did the
  loot actually land" is to the bot's whole purpose.
  - **Re-verify `retryClickAfterMs=2600` against this NPC's actual
  kill-color linger time live** (the way AutoFighter's own 4000ms value was
  originally tuned) — don't assume the copied value is correct for a
  different target without checking, per the stale-signal gotcha in
  `ARCHITECTURE.md`.
- **Narrow `lootSearchWidth/Height`** from near-full-screen to a smaller
  region around where the ground-item text actually renders (likely near
  the NPC's death location or a fixed on-screen chat/overlay area) — cuts
  per-poll `ImageSearch` cost during stage 1/2 waits.
- **Consider extending `LootPickupPhase` to a generic multi-item loot table**
  if this bot is ever adapted to a spot that drops more than one recognizable
  item — today it's hardcoded to exactly one item/anchor pair
  (`bb-item.png`/`take-bb.png`), unlike a more general "scan a loot list"
  design.
- If a stage beyond 3 is ever added, **add an explicit `stage == 3` guard**
  (rather than relying on the implicit else) so an unexpected `lootStage`
  value fails loudly instead of silently running stage-3 logic.
