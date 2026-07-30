# v7 full rewrite — starter prompt (paste this as your first message in a new session)

Continuing the OSRS automation project (AutoHotkey v2, repo root: this folder).
v6 works — woodcutting, motherlode2, crafting, smithing, sudoku, autoclicker,
and seller are all functional end-to-end bots built LEGO-style on shared
primitives in `Lib\`. This session's job is a **complete rewrite from
scratch**: new `Lib\`, new `micro\` validators, new `Bots\`. Not a patch, not
an incremental refactor of the existing files — a clean v7 built with
everything learned from v6, informed by a full codebase audit already done
(summarized below so you don't have to re-derive it).

**Do not start writing code immediately.** Follow the process at the bottom,
in order. Step 1 is a list-and-confirm step, not an implementation step.

## Repo layout for v7 — different from the v5→v6 transition

Last time (v5→v6), the old version was deleted and the new one was promoted
to the repo root directly. **Do NOT do that this time.** v6 stays exactly
where it is (`Lib\`, `Bots\`, `micro\`, `logs\`, `Images\` at repo root,
completely untouched, still runnable as a working fallback) while v7 is built
side by side in a **new top-level `v7\` folder**, mirroring the same internal
layout: `v7\Lib\`, `v7\micro\`, `v7\Bots\`, `v7\logs\`, `v7\Images\`. Only
after v7 is proven live should promotion/deletion of v6 even be discussed —
that decision is explicitly out of scope for this rewrite itself.

## What NOT to change

The basic structure worked. Keep:
- The 3-layer LEGO architecture: `Lib\` (primitives + composites) → `micro\`
  (one standalone validator script per primitive/composite) → `Bots\` (full
  gameplay loops composed from Lib calls).
- The hotkey convention: F5 start, F6 stop (interrupts instantly, even
  mid-search/mid-wait), F8 probe/diagnostic, F12 exit bots (never Esc — some
  bots send a real Esc as an in-game action). Micro scripts may still use Esc
  to exit since they don't send in-game Esc.
- `Pause()` as the only sleep primitive anywhere (interruptible, checks
  `g_StopRequested`, throws `BotStopped`) — never a raw `Sleep()`.
- One log file per bot/micro run (`g_LogName` + `TrimLogOnStart()`), `Say()`
  for user-visible + logged messages, `LogLine()` for log-only.
- Corner-measured coordinates as the calibration convention: a marker/area is
  defined as `X, Y` (top-left corner) + `W, H`, never a pre-computed
  `[x1,y1,x2,y2]` array typed out with inline arithmetic (that style was
  retrofitted into motherlode2.ahk in the previous session specifically to
  eliminate hand-written arithmetic literals — keep going that direction,
  don't regress).

## The main search function — confirmed contract (2026-07-22)

Design the v7 search primitive(s) around these 9 modes as the full contract.
This may end up as one function with a mode/opts switch, or several thin
functions sharing a core — that's an implementation decision for later, not
now. The modes:

1. Search by color (solid block of a given size/tolerance).
2. Search by image (PNG, optional transparent color).
3. Whole-screen search, flat single pass (color or image) — no reference
   point, no staging.
4. Whole-screen search via expanding rings from a reference point: try a
   small box around the ref point first, widen in stages, whole-screen only
   as the last-resort fallback. (Today's `AcquireClosestInBox` / micro-03
   shape — keep this, don't collapse it into mode 3.)
5. Region-limited search: a given W×H box at a given X,Y, looking for a
   block/image of a given size (color or image).
6. Exact-point verification: confirm a block/image of a given size is
   present AT specific coordinates — not a roaming search, a presence check
   at one known point. (Today's `BlockAtPoint` shape — used for "did we
   arrive/does the marker still match here.")
7. Click lands exactly at the found match's **computed center** — no
   click-offset compensation constants anywhere in v7. If a bot needs one,
   that's a signal the search coordinates/sizes were measured wrong, not a
   feature to build in. (v6's `*_CLICK_OFFSET_*` pattern, confined entirely
   to motherlode2.ahk, should not reappear in v7 — re-measure instead.)
8. Tracked-block mode: acquire a target, keep re-locating the same block as
   it moves/depletes, re-click on cadence, detect depletion, re-acquire,
   until an until-condition. (Today's `TrackAndClick`.)
9. Two-stage marker→action: find color/image A, then after a **configurable
   delay in ms**, perform the click — either at fixed coordinates, or by
   searching for a different color/image B and clicking that. The delay must
   be a named, tunable parameter, not a bare `Pause()` sitting outside the
   function.

### Confirmed: color-block search is already exactly as fast as image search

Verified directly in v6's `Lib\Find.ahk` (2026-07-22) — no need to re-derive
or re-litigate this in v7 design discussions. `FindFilledBlock` does NOT do
a slow pixel-by-pixel scan; it builds (and caches, per color+size, via
`SolidBlockBitmap`) an in-memory GDI bitmap of the solid color, then calls
the exact same native `ImageSearch` API that `FindImage` calls against a
loaded PNG. The file's own header documents this was a deliberate "SPEED
OVERHAUL (2026-07-19)": the previous pixel-search-based verify-and-split loop
cost ~7ms per rejected candidate (42 decoy-colored UI specks cost ~3s live);
replacing it with one `ImageSearch` call made whole-screen color search run
at a constant ~100-200ms regardless of what else is on screen — the same
cost class as an image search. **v7 should keep this synthesized-bitmap
approach for color search rather than reintroducing a pixel-by-pixel path.**

One real caveat, not a color-vs-image asymmetry: `AcquireClosestInBox`
(multi-candidate-color acquire, mode 4/8's tie-break) calls `FindFilledBlock`
once per candidate color in a loop, so a 2-color acquire costs roughly 2x a
single search — that scaling is inherent to checking N colors, not evidence
that color search itself is slower than image search.

## Motherlode-proven resilience patterns — design these in as first-class Lib behavior, not per-bot workarounds

`Bots\motherlode2.ahk` (and `Steps.ahk`'s composites built for it) developed
several retry/resilience mechanisms live, against a real shared/laggy game
resource (the hopper) and a real moving/jittery target (veins). These are
proven-necessary, not speculative — carry them into v7's composite designs
as reusable, named options, not something each bot re-invents:

- **Patient-first-wait, then re-click forever** (`ClickUntilCondition`): the
  first click after an action gets a generous, patient wait; only if that
  times out does it downgrade into re-clicking on a shorter cadence. Exists
  because some UI state changes are laggy/queued (a backed-up hopper still
  draining) — a miss isn't necessarily "the click failed," it can mean "not
  your turn yet."
- **Stall-after-retry heuristic** (motherlode2's `g_HopperWasFull`): if a
  retry-loop like the above ever needed its re-click fallback, that's a
  signal worth propagating to the caller (confirmed live: a hopper deposit
  that needed retries was followed by mining stalling hard afterward,
  clicking the same vein repeatedly with zero progress) — the caller can
  then choose to bail to a different phase instead of pushing forward blindly.
- **Dual-timeout pattern** (`TrackAndClick`'s `progressTimeoutMs` vs
  `timeoutMs`): a single fixed total-time cap kills healthy-but-slow runs
  identically to genuinely stuck ones. `progressTimeoutMs` resets on any real
  activity signal (acquire/depletion/click) and is the actual "stuck" check;
  `timeoutMs` stays only as a generous absolute backstop underneath it.
- **Drift-reject** (`maxDriftPx` vs `trackRadius`): when re-locating a
  tracked target, a match far from the last known position is probably a
  DIFFERENT same-colored neighbor, not the real target having moved that far
  — reject and treat as "still there, just occluded" rather than switching
  targets. `trackRadius` is the search net (how far to even look);
  `maxDriftPx` is the suspicion check applied after a match is found inside
  that net.
- **Anchor-hold** (hard rule in `TrackAndClick`'s track mode): if the search
  misses this tick but the exact point last clicked is STILL the target
  color, hold the current target rather than conceding depletion — a miss
  can be transient occlusion, not real depletion.
- **Stability gating before clicking** (`TargetLock`): require N consecutive
  in-tolerance ticks before treating a target as "stable" enough to click on
  the normal cooldown; an unstable target still gets clicked on a slower
  re-click cadence so progress isn't blocked, just paced differently.
- **Whole-screen diagnostic fallback on arrival-miss** (`TravelToPoint`): if
  arrival-at-exact-point never confirms, do one whole-screen search for the
  same marker anyway and log whether it was found elsewhere (region/position
  was wrong) vs not found anywhere (marker genuinely never appeared/timing
  issue) — this distinction is what makes a stuck bot's log diagnosable
  instead of just "it timed out."
- **Per-slot content verification with auto-correction** (motherlode2's
  pay-dirt pointer walk): rather than a blanket "is inventory full" check,
  walk expected-content slots one at a time; a slot that doesn't match
  expected content gets corrected (shift-click dropped) and re-checked before
  advancing. Generalizable beyond gems-in-a-mining-inventory to any
  "verify each newly-filled slot, correct if wrong" shape.

## Universal requirement: every action owns its own timing

Every function in the new Lib that performs a click, keypress, or other
game-affecting action must expose its own pre-action and post-action delay
as **optional parameters, default 0 (no-op)** — visible and tunable directly
in the function call, not as a bare `Pause()` sitting in a bot file between
two Lib calls. This was partially attempted in v6
(`.claude\ADD_DELAY_PARAMS_PROMPT.md` — read it, it's still a valid partial
spec) but never finished. Concrete v6 instances to learn from (don't
reproduce in v7):
- `Lib\Act.ahk`'s `ClickAt` hardcoded its settle/ctrl-hold timing as
  file-local `static` constants, explicitly NOT caller-configurable. v7's
  equivalent should expose these as real parameters with the same defaults,
  so a bot author can tune them without touching Lib code.
- `Bots\seller.ahk` reused one flat `STEP_DELAY_MS` as 5 separate bare
  `Pause()` calls between structurally different transitions (post-image-wait,
  post-click, post-hotkey) — no per-transition tuning was possible. v7's
  composites should make each transition's delay its own named parameter.
- `Bots\sudoku.ahk` (2 bare `Pause()`s) and `Bots\smithing.ahk` (1 bare
  `Pause(DEPOSIT_SETTLE_MS)` after `RunRestockPlan`) have the same pattern.
- `Lib\Steps.ahk`'s `ClickUntilCondition` already does this correctly via its
  `firstSettleMs` param — use it as the reference shape for "what a
  well-designed settle parameter looks like."

## Other confirmed v6 anti-patterns to design out (not fix in place — v6 stays frozen)

- **Region support was inconsistent.** `FindFilledBlock`, `FindImage`,
  `AcquireClosestInBox`, `BlockAtPoint`, `TakeSnapshot`/`HasChanged` all take
  an explicit box. `IsColorAt` and the whole `Inv.ahk` fullness family
  (`SlotFull`, `AnySlotEmpty`, `AllSlotsFull/Empty`) are single-point/fixed-
  sample only with no box option. Decide deliberately in v7 whether that's a
  real, justified exception (slot positions are computed, not searched) or
  something to unify — don't leave it as an accident.
- **Whole-bot duplication.** `Bots\smithing.ahk` and `Bots\crafting.ahk` are
  the same bot copy-pasted, differing only in calibration values (colors,
  coords, sizes, restock-plan entries, one stray settle pause, poll interval).
  The `README.md` already flags this as a known gap: a `Config\` directory
  exists but is unused, and each bot hardcodes its own calibration block
  instead. v7 should decide explicitly: one config-driven bot file per
  *shape* (e.g. one generic "craft-loop" bot fed by a config), not N copies
  of the same logic.
- **Duplicated non-config constants.** e.g. deposit-image path/dimensions
  redefined identically in both crafting.ahk and smithing.ahk instead of
  shared once.
- **Stale docs.** `README.md`'s status section and
  `.claude\NEXT_SESSION_PROMPT.md` both predate most of the current bots and
  should not be trusted as current-state references — they need to be
  rewritten as part of (or immediately after) this rewrite, not treated as
  input specs.

## Known gaps: micro-actions that may need to be ADDED, not just ported

The current 13 micro scripts (`micro\01` through `micro\13`) each validate
exactly one Lib primitive/composite — see the mapping in this session's
audit (ask to see prior conversation context if not already available, or
re-derive from `Lib\*.ahk` + `micro\*.ahk` headers). `TEMPLATES.md` (the
original plain-English spec for 10 bots, several of which — AutoFighter,
AutoFighterLoot, FruitStall, Agility, Firemaking, Smelter — were never built
in v6) names building-block behaviors that have **no current Lib primitive
and no current micro validator**:
- **FindBlob** — nearest irregular-shape color blob (NPC overlays), as
  opposed to a solid rectangular block. Needed for AutoFighter/
  AutoFighterLoot if either is ever built.
- **Combat/state-indicator watching** — watch a pixel for one of several
  meaningful colors (fighting / kill-confirmed / idle), with a "was this
  already true when we started watching" guard (corpse-lingers-3s case in
  TEMPLATES.md's AutoFighter spec).
- **Right-click → context-menu-item click** — AutoFighterLoot's loot-pickup
  flow needs a right-click + a follow-up click on a context menu entry,
  distinct from the left-click-only `ClickAt` that exists today.

Decide during Step 1 (below) whether these are in scope for this rewrite or
explicitly deferred.

## Process — follow in this order, confirm with the user between each step

1. **Compile the complete micro-action list.** Start from the 13 that exist
   today (mapped above) plus the 3 gaps just listed, cross-check against
   every current `Bots\*.ahk` file's actual behavior (not just
   `TEMPLATES.md`, which predates several bots) to make sure nothing already
   built is missing a corresponding micro-action. Present the full list back
   to the user for confirmation before writing anything. This is a
   list-and-confirm deliverable, not code.
2. **Build the new micro scripts one at a time, live-confirmed before moving
   to the next** — same pacing v6's own "Stage 1" used (per project memory:
   micro-script-first pacing, each gated on live in-game confirmation, not
   "looks right in the code"). Don't batch-write all micro scripts and test
   them together at the end: write `v7\micro\01-...`, confirm it live in
   RuneLite, THEN write `02-...`, and so on. This is deliberately slower
   per-script than batching, but it's the pacing that already worked for v6
   and catches calibration/behavior mistakes one at a time instead of
   compounding them.
   - One place this can likely move faster than v6's original Stage 1: the
     underlying Windows APIs (`ImageSearch`/`PixelSearch`/`ClickAt`'s mouse
     mechanics) aren't changing, so scripts that are pure re-shapes of an
     already-proven v6 primitive (e.g. porting `FindFilledBlock` itself) may
     need less exploratory back-and-forth than v6's original from-scratch
     discovery did. Scripts introducing genuinely new contract surface (the
     unified pre/post-pause params, the 9-mode search function, any of the
     newly-added gap primitives like FindBlob) should get the full same
     live-confirmation rigor as v6's originals, since those ARE new
     behavior, not ports.
   - If a better sequencing turns out to make more sense once the full list
     from Step 1 is in hand (e.g. building a couple of closely-related
     primitives together because one can't be meaningfully tested without
     the other), propose that explicitly and get confirmation before
     deviating — don't silently batch for convenience.
3. **Build the new bot scripts from scratch**, composing the new Lib on top
   of the confirmed micro-actions. Only after 1 and 2 are both done and
   confirmed.

Do not skip ahead to step 3 (or even step 2) without the user explicitly
signing off on the prior step's output.
