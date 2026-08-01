# v7 rewrite — progress / continuation notes

Read this file first in a new session before touching this codebase. As of
2026-07-23, v7 was promoted to the repo root and the old v6 codebase moved to
`legacy\` (frozen fallback, not touched going forward) — see
[`legacy/prompts/V7_REWRITE_PROMPT.md`](legacy/prompts/V7_REWRITE_PROMPT.md)
for how/why the rewrite started. Full plan lives at
`C:\Users\link\.claude\plans\v7-full-rewrite-parallel-possum.md` — this file
is the fast-resume supplement, not a replacement.

## Where things stand

**ALL 26 MICROS BUILT AND LIVE-CONFIRMED (2026-07-23). Step 2 is
COMPLETE — next up is Step 3: build `Bots\`.**

**2026-07-27: WindMouse integrated, then replaced 2026-07-30 (standard
#29). All game-input cursor movement glides via `HumanMove` in
`Act.ahk` now — a minimum-jerk (Flash & Hogan) model promoted from
`Tools\humanized-mouse.ahk`, not WindMouse.** WindMouse's physics-glide
(gravity+wind, continuous curvy wander) went through a same-day tuning
saga on 2026-07-27 (too slow → retuned physics → still slow → traced to
Windows' ~15.6ms `Sleep` rounding silently eating the step-delay knob →
`timeBeginPeriod` attempted, made it WORSE (doesn't tighten AHK's own
`Sleep`) → real fix was a `QueryPerformanceCounter` busy-wait instead of
`Sleep`/`Pause` for per-step pacing). That busy-wait technique is still
correct and still in use (renamed `GlideStepDelay`) — but on 2026-07-30,
live feedback made clear the WindMouse *algorithm itself* (continuous
curvy physics wander) was never going to feel right: the user plays
like an expert who already knows exactly where every UI element is —
near-instant, almost-direct movement, tremor only leaving rest and
settling on target, not throughout. WindMouse (`WindMouseGlide`/
`WindMouseMove`, the 5 `WINDMOUSE_OVERSHOOT_*` overshoot-and-correct
constants) was deleted outright and replaced with `HumanGlide`/
`HumanMove` — see standard #29 below for the full design (edge-only
tremor via `TremorWeight`, no ballistic-miss/correction phase since
`BlockJitterPx`/`JitterPoint` already jitter the aim point upstream,
and the worked speed arithmetic that keeps this project from repeating
the "retuned blind, still slow" mistake a second time). Also added,
then REMOVED same day: `IdleWander` (small random cursor hops during
long idle stretches, wired into `TrackAndClick` only, opt-in via
`idleWanderAfterMs`) — live-tested, didn't work as intended, ripped
out entirely (`IdleWander`/`IDLE_WANDER_*` gone from `Act.ahk`,
`idleWanderAfterMs` gone from `TrackAndClick`, `micro\28-idle-wander`
deleted). Not worth re-attempting without a clearer idea of what
specifically felt wrong about it.
NOT yet live-reconfirmed after the 2026-07-30 rewrite — live-confirm
order: micro 27 (renamed `27-human-move`) → 08 (modifier reorder) → 10
(coordless right-click) → 18 (shift-after-glide drop) → 21 (coordinate
staleness + single-click behavior) → full woodcutting run. Watch-for:
`TrackAndClick` coords can be stale at
click time by roughly one glide's duration (remedy if misclicks appear:
post-glide re-probe, not constant tuning — same watch-for as before,
just now bounded by `HumanMove`'s much shorter worst-case glide time
instead of WindMouse's). A full Lib audit ran
as the pre-Step-3 gate (standard #24): opts unpacking deduped via
`Opt()`, `POLL_MS_DEFAULT := 100` everywhere, `ScreenRegion()`,
`FindAndClickBlock`/`Image` merged onto a shared `WaitThenClick`
engine, Lib margin defaults aligned to 0, comments compressed. All 26
micros re-validated clean afterward. Micro 18 (the old
"wait-marker-then-click" M9 two-stage shape) was DROPPED — live testing
showed it duplicated micro 11's `FindAndClickBlock` with a `clickX`/
`clickY` pin, which already covers "wait for a marker, click a
different point." The remaining micros (old 19–27) were renumbered down
by one to close the gap.

Micro 25 (gather-bank-loop) is LIVE-CONFIRMED — `GatherBankLoop` added
to `Steps.ahk`, plus a new `SearchZone` mode switch in `Find.ahk`
(standard #22) so a script's marker/deposit region can flip between
full/area/fixed via ONE object-literal swap (`MARKER_ZONE := {mode:
"full"|"area"|"fixed", ...}`) instead of hand-editing constants. All
three `SearchZone` modes confirmed working live, plus the
gather→bank→gather cycle repeating correctly.

Micro 26 (bot-harness) is LIVE-CONFIRMED — `InstallBotHarness` added to
a NEW `Lib\Bot.ahk`, wiring F5=start/F6=stop/F12=exit plus optional
F8=probe and `extraHotkeys` in ONE call, fixing the F5/F6/F12
boilerplate every v6 bot hand-rolled separately. Log-confirmed: clean
start→tick, F6 stop, restart-from-tick-1 (not resuming), F8 probe
mid-run without interrupting ticks, F9/F10 each firing only their own
handler (no cross-fire — see standard #23 for the closure bug this
proves was avoided), and F12 exit. v6 (repo root) is untouched and
still the working fallback for the whole rewrite.

Micro 21 (`TrackAndClick`, the biggest composite in the project) surfaced
two real bugs during live testing that are now fixed and documented in
`Lib\Steps.ahk` directly above `TrackAndClick` — read standards #15/#16
below before tuning `trackRadius`/`maxDriftPx`/`postClickSettleMs` on any
future bot that uses this composite.

Micro 24 (`DepositAllToBank`/`RunRestockPlan`) required real Lib growth,
not just a port: `FindAndClickImage` was added BACK to `Steps.ahk` (it
had been deliberately cut earlier for lack of a caller — this is that
caller), and `BANK_DEPOSIT_IMAGE_*` was added as a Lib global in
`Find.ahk`. Read standard #17 below carefully before touching bank/UI
landmark constants again — there was a real back-and-forth correction
on exactly what is/isn't a fixed screen position.

Build-order rule in force: Lib is assembled incrementally, ONE function (or
tightly-coupled group) per micro, in lockstep with the micro that exercises
it. Never write a Lib function ahead of its micro. `Lib\v7.ahk` is the
umbrella include — every new file gets one `#Include` line added there.

## Confirmed calibration constants (this user's setup)

Screen: 2560×1440. These live in `Lib\Find.ahk` / `Lib\Inv.ahk` —
do not redefine them per script, reference them.

- `GAME_ZONE_X1/Y1/X2/Y2` = `0, 45, 2499, 1380` (game viewport sub-region,
  not full screen) — `GameZoneRegion()` accessor.
- `CHAR_X/CHAR_Y` = `1249, 712` (character's on-screen center, fixed
  camera/zoom).
- `ACQUIRE_PADDING_SMALL/LARGE` = `64, 128` (ring-expand defaults, M4).
- `INV_GRID` = `GridSpec(2099, 801, 4, 7, 72, 64, 12, 8)` in `Inv.ahk` —
  same numbers v6 measured, reconfirmed live on this setup via micro 13.
- `BANK_GRID` = `GridSpec(625, 203, 999, 1, 72, 64, 24, 0)` in `Inv.ahk` —
  single-row only (v6's own measured limit, not yet extended to a real
  second row).
- `BANK_DEPOSIT_IMAGE_X/Y/W/H` = `1327, 963, 72, 72` in `Find.ahk` — the
  deposit-all PNG button's fixed position (see standard #17 — this is
  the ONLY bank/UI position that's a Lib global; the deposit-box marker
  itself is NOT fixed and stays per-script).
- `SLOT_FULL_OFFSETS/SLOT_EMPTY_COLOR/SLOT_EMPTY_TOL` = v6's values
  (`0x3F3629`, tol 5) — confirmed still correct (UI skin color, not a
  screen coordinate, so expected to be resolution-independent).

## Standards established along the way (apply to every future micro/bot)

1. **Colors are always an array.** `TARGET_COLORS := [c]` even for a
   single-color script — never a scalar `TARGET_COLOR`. Search primitives
   split accordingly: `FindAnyFilledBlock`/`IsAnyColorAt` (no reference
   point, list-order first match) vs `AcquireClosestInBox` (reference
   point, proximity tie-break, used by ring-acquire M4). Images stay
   single-path (a different image asset has its own w/h — no array).
2. **One corner-measured position input, never a hand-typed center.**
   `MARKER_X`/`MARKER_Y` (top-left corner) is the only "EDIT THESE" position
   constant; the center is always derived via `CenterX`/`CenterY`
   (`Core.ahk`) right after the edit block, never re-typed.
3. **`AREA_X/Y/W/H` (micro 04's shape) is a DIFFERENT concept from
   `MARKER_X/Y` + a known `BLOCK_W/H`** — area = a rough box bigger than an
   unknown-ish position; marker = a specific block at a specific known
   corner, padded only by small `MARGIN_PX` slack. Don't conflate them.
4. **F5 always starts, F6 always requests stop** (sets `g_StopRequested`,
   logs, standard across every micro — no more "F6 = clear tooltip").
   Every run-function resets `g_StopRequested := false` at its own start,
   matching micro 01/08's pattern.
5. **Micros exit via Esc**, EXCEPT any micro that itself sends a real Esc
   as a test action (09, 10) — those use **F12** instead, to avoid the
   script's own `Esc::` hotkey re-triggering off its own `Send("{Esc}")`.
6. **No click-offset compensation constants anywhere.** A mis-click means
   re-measure the marker, not add an offset. `clickX`/`clickY` PINNING
   (an explicit override to click a static point instead of the found
   position) is a different, legitimate concept and stays.
7. **`ClickAt`'s Ctrl/Shift release is async** (a background timer via
   `SetTimer`, not a blocking `Sleep(holdMs)`) — holding a modifier costs
   no real time. `ReleasePendingModifiersNow()` is the guard every action
   function (any future one too) must call at its own start, so a modifier
   still pending release from a previous click can never bleed into the
   next action. `g_PendingModifierKeys` (Act.ahk) tracks this.
8. **Every action function takes `preDelayMs`/`postDelayMs`** (default 0,
   routes through `Pause` so it's F6-interruptible) bracketing the whole
   action. Mechanical gaps like `settleMs`/`holdMs` stay `Sleep` (not
   interruptible) since they're not a caller's scheduling choice.
9. **Composites with many named optional fields use the opts-object style**
   (a plain object, matching v6's convention) — e.g. `FindAndClickBlock`,
   `RightClickMenuItem`. Simpler primitives (`ClickAt`, `PressKey`,
   `BlockAtPoint`) stay positional-args.
10. **Don't keep speculative/untested Lib code.** `FindAndClickImage` was
    written then deliberately deleted — it didn't map to any confirmed use
    case. Add it back only when a real scenario needs it.
11. **`RightClickMenuItem` needed a `menuSettleMs`** (gap after the
    right-click, before the FIRST menu-item search attempt) — without it,
    the first search fires with zero gap and reliably misses, forcing a
    full wasted `pollMs` wait. This is a real lesson if any future
    composite does "act, then immediately search for the result."
12. **Don't build a new composite before checking an existing one already
    covers it.** Micro 18 (`WaitMarkerThenClick`) was written, then
    dropped once live discussion showed `FindAndClickBlock` (micro 11)
    with a `clickX`/`clickY` pin already does "wait for a marker, then
    click a different point" — the only thing the new composite added was
    one extra `ClickAt` before the wait, which isn't Lib's job (a bot
    just calls `ClickAt` then `FindAndClickBlock` pinned). Check for
    overlap with confirmed composites before writing a new one.
13. **Primitives positional, composites opts** (formalized in the
    2026-07-23 review pass): every `Steps.ahk` composite takes ONE opts
    object — `RightClickMenuItem` was converted from 14 positional params
    to opts to match `FindAndClickBlock`/`ClearAllInstances` (micro 10's
    call site updated, behavior identical, re-validated via
    `/validate`). Detection/action primitives (`Find`/`Act`/`Grid`/`Inv`)
    stay positional. Shared opts field names are standardized:
    `path`/`w`/`h`/`tol`/`transColor` (image spec),
    `colors`/`tol`/`blockW`/`blockH` (block spec), `ctrl`, `settleMs`,
    `waitTimeoutMs`, `pollMs`, `label`, `preDelayMs`/`postDelayMs`.
14. **Syntax-check without running:** `AutoHotkey64.exe /ErrorStdOut
    /validate <script>` parses a script (including its `#Include`s, so
    Lib gets covered by validating any micro) without executing it.
    NOTE: run it from PowerShell, not Git Bash — Git Bash mangles the
    `/validate` switch into a path. All 24 micros pass as of 2026-07-23.
    Re-validate after every Lib edit, not just after writing a new micro.
15. **`trackRadius` (TrackAndClick) must stay under roughly HALF the real
    gap to the nearest SAME-colored duplicate — not just `maxDriftPx`.**
    Track mode's re-search is a single-color `FindFilledBlock` call;
    if `trackRadius` is big enough that a same-colored neighbor falls
    inside that search box, WHICH instance gets found each tick is
    scan-order-arbitrary, not proximity-based — `maxDriftPx` can only
    reject a bad match after the fact, it can't make the search return
    the right one in the first place. Confirmed live: two real veins
    46px apart (same color by design — this user's convention is
    same color when there's a gap, distinct colors only when veins are
    directly adjacent with no gap) jumped between each other with
    `trackRadius=96`. Fixed by shrinking `trackRadius` well under half
    the real measured gap (e.g. ~16-20 for a 46px gap).
16. **`postClickSettleMs` (TrackAndClick, default 0) exists to compensate
    for v7's async Ctrl release removing a timing cushion v6 had for
    free.** v6's `ClickAt` blocked synchronously for `holdMs` (~100ms)
    before returning; v7's returns immediately (a deliberate, confirmed
    improvement from micro 08 — holding a key costs no real time). That
    incidentally meant v7's next re-search now fires ~100ms SOONER after
    a click than v6's did. If the real target has any brief post-click
    visual flicker (a hit animation frame, a client-side highlight),
    that tighter timing can catch it mid-flicker and falsely declare a
    perfectly healthy target "depleted." Confirmed live: a vein that does
    NOT deplete was reported depleted after literally every single
    click, fixed by setting `postClickSettleMs` (a real pause after each
    click, before the loop's next re-search) to ~100-150ms.
17. **What counts as a "fixed Lib global" vs "per-script config" — get this
    exactly right, it was corrected live more than once on micro 24.**
    ONLY a genuinely fixed screen position belongs in Lib as a global
    (same category as `GAME_ZONE_*`/`CHAR_X/Y`/`INV_GRID`) — e.g. the
    deposit-all PNG BUTTON (`BANK_DEPOSIT_IMAGE_X/Y/W/H`, `Find.ahk`),
    which sits at the same spot no matter which bot opens a bank. The
    bank/deposit-box MARKER (a colored block the bot searches for/clicks
    to open the bank) is NOT fixed like that — it can differ per bank
    location — and stays full per-script config (color, position, size,
    margin all local), same shape as micro 06/11's marker. A truly fixed
    position also needs NO margin at all (`RegionAround(..., 0)`) since
    it never drifts — margin (`MARGIN_PX`) is a camera-drift compensation
    that only makes sense for a search-based marker whose real on-screen
    spot can shift slightly, not for a coordinate that's simply always
    correct.
18. **`MARGIN_PX`/`POS_TOL_PX`-family values default to 0, not some
    nonzero "safe" number.** Checked across every confirmed micro
    (04/06/07/09/11/16/20) — none hardcode a nonzero default; a value is
    only raised once live testing actually shows drift. When a script
    has 2+ distinct search targets needing their own margin (e.g. micro
    24's marker AND deposit image), prefix each with its role
    (`MARKER_MARGIN_PX`, `DEPOSIT_MARGIN_PX`) — single-target micros stay
    unprefixed (`MARGIN_PX`).
19. **`FindAndClickImage` came back** (micro 24) after being deliberately
    cut earlier (standard #10) — `DepositAllToBank` is the confirmed real
    caller the cut was waiting for. Same shape as `FindAndClickBlock` but
    for a PNG (`FindImage`) instead of a color block; no click-offset
    compensation, same as its block sibling.
20. **`RunRestockPlan` takes a plan ARRAY (`[[slot, clicks], ...]`), never
    a single `[slot, clicks]` pair.** Matches v6's own
    crafting.ahk/smithing.ahk shape — lets one call restock multiple bank
    slots with different click counts in one pass. Don't flatten this
    back down to two scalar constants even for a single-slot test.
21. **Repeated config SHAPE across micros (same field names/order for
    "a marker") is intentional consistency, not duplication to eliminate.**
    The actual reusable logic lives once in Lib and never repeats; each
    micro's local EDIT-THESE constants necessarily hold different real
    calibration values (colors/coordinates), so the values can't be
    shared — but the shape repeating (`colors/tol/blockW/blockH/x/y/
    marginPx/waitTimeoutMs`, always in that order) is what makes every
    new micro immediately legible. Don't "fix" this by bundling the
    shape into a constructor/struct — that would hide values behind
    positional args again, undoing the opts-object transparency work
    (standard #13) and the "every value visible even at default" rule
    (standard #18).

22. **`SearchZone(opts)` (`Find.ahk`, added micro 25) collapses a script's
    region-building decision into ONE `mode` field** (`"full"` = whole
    game viewport via `GameZoneRegion()`, `"area"` = a rough box bigger
    than the target, `"fixed"` = an exact box the target's own size —
    the same three shapes standard #3 already named — and `"quadrant"`,
    added 2026-07-23: one quarter of the game zone, via
    `opts.quadrant: "top-left"|"top-right"|"bottom-left"|"bottom-right"`.
    `GameZoneQuadrant(which)` splits `GameZoneRegion()` around `CHAR_X`/
    `CHAR_Y` — the fixed player-center calibration, NOT a recomputed
    geometric midpoint, so the split is guaranteed to pass through the
    character's own point by construction even if `GAME_ZONE_*` is ever
    re-measured asymmetrically (confirmed: they currently coincide
    exactly — `(0+2499)//2, (45+1380)//2` = `1249,712` = `CHAR_X,CHAR_Y`).
    Use `"quadrant"` when you know roughly which corner of the screen a
    marker lives in but haven't measured exact bounds. Added because
    switching a script between them by hand meant deleting/re-adding
    whichever `X/Y/W/H` constants that mode needs, and a `RegionAround(...)`
    call left referencing a deleted constant breaks the whole script.
    **Caller contract (CORRECTED live 2026-07-23):** do NOT keep separate
    `MARKER_AREA_X/Y/W/H`-style globals and conditionally copy them into
    the opts object based on mode — AHK v2's "variable never assigned"
    check is a WHOLE-FILE static scan, not a per-branch runtime one, so a
    global only assigned inside a commented-out line still gets flagged
    even when the branch that reads it never executes (confirmed live:
    `MARKER_AREA_X` warned while mode was `"full"`, i.e. that branch was
    dead code). Instead, write ONE opts object literal PER MODE inline,
    right where the mode is chosen, and comment out the other modes'
    lines:
    ```
    MARKER_ZONE := {mode: "full"}
    ; MARKER_ZONE := {mode: "area", x: 693, y: 229, w: 708, h: 636, marginPx: 0}
    ; MARKER_ZONE := {mode: "fixed", x: 1044, y: 928, w: 15, h: 15, marginPx: 0}
    ```
    then pass it straight through: `markerRegion := SearchZone(MARKER_ZONE)`.
    Exactly one assignment to `MARKER_ZONE` ever exists in the file, so
    there's nothing for the check to flag, and the other modes' x/y/w/h
    live as object-literal fields (not separate globals) so they're never
    independently "unassigned" either. **Scope decision (2026-07-23):
    forward-only** — micros 1–24 stay exactly as confirmed, not
    retrofitted; `SearchZone` applies starting with micro 25, and forward
    into 26 and every `Bots\` script in Step 3.

23. **`InstallBotHarness(opts)` (`Bot.ahk`, added micro 26, the last
    micro before Step 3) is the ONE call every future bot uses instead
    of hand-rolling F5/F6/F12** — fixes the exact 7-way duplication
    across v6's autoclicker/crafting/motherlode2/seller/smithing/sudoku/
    woodcutting (each had its own byte-identical stop-flag-reset +
    `try/catch BotStopped` + F5/F6 registration, only the loop body
    differed). `opts.run` should NOT catch `BotStopped` itself — let it
    propagate up to the harness. `opts.probe` (F8) and
    `opts.extraHotkeys` (array of `{key, handler}`, e.g. motherlode2's
    F9 debug toggle) are both optional extension points.
    **Closure-per-entry pitfall (confirmed by design, not live bug):** a
    naive `for entry in opts.extraHotkeys { Hotkey(entry.key, (*) =>
    entry.handler()) }` would be wrong — AHK v2's `for` loop variable is
    one reused local, not a fresh binding per iteration, so every extra
    hotkey's closure would end up calling whichever handler was
    registered LAST once any of them actually fires (long after the
    loop finished). Fixed via a `BindHotkeyHandler(handler)` factory —
    `handler` is a genuine parameter of that call, so each call gets its
    own distinct local to capture. Live-confirmed (2026-07-23, micro 26
    log): F9/F10 registered via this factory each fired only their own
    message, never the other's.

24. **Config visibility + Lib audit (2026-07-23, pre-Step-3 gate).** Every
    new script's EDIT block displays ALL tunables, even at their
    defaults: `MARGIN_PX := 0`, `VERIFY_PERCENT := 100`,
    `POS_TOL_PX := 0`, `POLL_MS := 100`, etc. — nothing hidden behind a
    Lib default the reader can't see. The audit itself changed:
    - `Opt(opts, name, default)` (`Core.ahk`) replaced ~60
      `HasOwnProp` ternaries — the ONE way composites unpack opts.
    - `POLL_MS_DEFAULT := 100` (`Core.ahk`) — every Lib `pollMs`
      defaults to it (was a mix of 300s), with ONE deliberate
      exception: `RightClickMenuItem`'s `pollMs` defaults to 150
      (now a configurable opt, no longer hardcoded) — measured live,
      the context menu takes at least ~150ms to open after the
      right-click, so a faster poll only wastes searches.
    - `ScreenRegion()` (`Find.ahk`) replaced 6 hand-built
      whole-screen arrays.
    - `WaitThenClick(findFn, opts, defaultLabel)` (`Steps.ahk`) — the
      shared wait→click→pin engine; `FindAndClickBlock`/`FindAndClickImage`
      are now thin wrappers over it (was real duplicated logic).
    - `RegionAround`/`BlockAtPoint` `marginPx` defaults changed 40 → 0
      (aligning Lib with standard #18). Every micro passed margins
      explicitly, so only `TravelToPoint`'s arrival check changed — its
      margin is now the visible `arriveMarginPx` opt (default 0); set it
      if a bot's arrival check turns flaky.
    - All Lib comments compressed to short versions pointing at these
      numbered standards instead of repeating the full war stories.
    All 26 micros re-validated clean after the rewrite.

25. **`TrackAndClick`/`DepositAllToBank` were missing `preDelayMs`/
    `postDelayMs` entirely** (found live building woodcutting, 2026-07-23) —
    standard #8 says every action gets them, but these two composites
    never threaded them through, so there was nothing to expose in a
    bot's config no matter how hard you looked. Fixed: both now take
    `preDelayMs`/`postDelayMs` (default 0), Pause at the very start, and
    `postDelayMs` only fires on the composite's own SUCCESS return (not
    on a timeout/no-progress/marker-or-deposit-not-found failure) — same
    convention `FindAndClickBlock`/`ClearAllInstances` already used.
    Every bot going forward should expose e.g. `GATHER_PRE_DELAY_MS`/
    `GATHER_POST_DELAY_MS` even at 0, not just assume the composite has
    nothing to bracket.

26. **Don't create a local alias for a Lib global just to satisfy a
    composite's own opts field name.** Woodcutting's first draft had
    `REF_X := CHAR_X` / `REF_Y := CHAR_Y` purely so `TrackAndClick`'s
    `refX`/`refY` opts had something short to reference — but `CHAR_X`/
    `CHAR_Y` are already the fixed Lib constant (same category as
    `GAME_ZONE_*`), so the alias was pure noise, not real per-script
    config. Pass `CHAR_X`/`CHAR_Y` directly into the opts object instead
    of re-declaring them under a new name.

27. **`deposit-box.png` (721,765,80×72) is a SEPARATE, real fixed Lib
    global (`DEPOSIT_BOX_IMAGE_PATH/X/Y/W/H`, `Find.ahk`) from
    `BANK_DEPOSIT_IMAGE_*` (deposit-bank.png, 1327,963,72×72, micro
    24)** — confirmed live 2026-07-23 these are two different real
    captures, not a duplicate to consolidate; both coexist, pick
    whichever matches the bank interface a given bot actually uses.

28. **A region built purely from fixed constants is itself a fixed
    constant — precompute it once in Lib, don't rebuild it per bot.**
    Woodcutting's first draft called `SearchZone({mode: "fixed", x:
    DEPOSIT_BOX_IMAGE_X, ...})` at its own top level just to get
    `depositRegion` — but every bot using `DEPOSIT_BOX_IMAGE_*` would
    need that identical call. Fixed: `Find.ahk` now also defines
    `BANK_DEPOSIT_IMAGE_REGION`/`DEPOSIT_BOX_IMAGE_REGION` (via
    `RegionAround(..., 0)`) right next to each image's X/Y/W/H — bots
    just reference the region constant directly, no `SearchZone` call
    needed for genuinely fixed assets.

29. **All game-input cursor movement flows through `HumanMove`
    (Act.ahk, micro 27)** — a minimum-jerk glide, the only movement
    path (no instant-move fallback). `ClickAt` and `RightClickMenuItem`
    are the only raw click sites and both glide; the diagnostic
    cursor-parking `MouseMove`s in micros are exempt (not game input).
    The glide is F6-interruptible (`GlideStepDelay` on every changed
    pixel), which is WHY `ClickAt` presses Ctrl/Shift AFTER the glide,
    not before: a mid-glide `BotStopped` would leak a held key that
    nothing tracks (`g_PendingModifierKeys` is only set after the
    click). Ends with an exact-landing snap — `ClickAt` clicks at
    current position, so 0px landing error is load-bearing.
    - **2026-07-27: first version was WindMouse** (BenLand100 physics
      glide, promoted from `Tools\windmouse.ahk`) — went through a
      same-day tuning saga (too slow → retuned physics, still slow →
      traced to Windows' ~15.6ms `Sleep` rounding silently eating the
      step-delay knob → `timeBeginPeriod` attempted, made it WORSE →
      real fix was a `QueryPerformanceCounter` busy-wait instead of
      `Sleep`/`Pause` for per-step pacing, since `timeBeginPeriod`
      doesn't tighten AHK's own `Sleep`). That busy-wait is still
      correct and still used today (see `GlideStepDelay` below) — the
      full postmortem is preserved in `Lib\Act.ahk`'s own comment above
      it and in this file's "Where things stand" section, since the
      *lesson* (Windows Sleep granularity, how to actually fix it)
      outlived the WindMouse algorithm itself.
    - **2026-07-30: WindMouse replaced entirely with `HumanMove`/
      `HumanGlide`**, promoted/adapted from `Tools\humanized-mouse.ahk`
      (deleted once promoted, same precedent as `Tools\windmouse.ahk`).
      Reason: WindMouse's continuous curvy physics wander never matched
      what was wanted — an expert who already knows exactly where every
      UI element is, moving near-instantly with tremor only leaving
      rest and settling on target, not throughout. `HumanGlide` is a
      minimum-jerk (Flash & Hogan) position blend along a subtly bowed
      arc — `MinJerk(t, skew)` (quintic, zero velocity+accel at both
      ends) drives a quadratic-Bezier blend toward the target, with
      per-sample tremor weighted by `TremorWeight(t, edgeFrac)` — the
      INVERSE of the source file's original mid-flight-peaked wobble:
      flat ZERO across the whole middle band, easing up to full
      `HUMANMOVE_TREMOR_PX` strength only in the first/last
      `HUMANMOVE_TREMOR_EDGE_FRAC` (0.15) of the path. No ballistic-
      miss/correction phase (the source file's own `HumanMove` had one)
      — `BlockJitterPx`/`JitterPoint` already pick a slightly-off aim
      point before this is ever called, so a second, independent aim-
      error model on top would double-humanize the same decision and
      cost real time for nothing. `HumanMove(x1,y1)` is now just a thin
      wrapper: `HumanGlide(x1,y1)`.
      Speed arithmetic (steps = `clamp(round(dist/HUMANMOVE_PX_PER_STEP),
      MIN,MAX)` = `clamp(round(dist/8), 5, 30)`, delay uniform in
      `[2,5]ms`, avg 3.5ms/step, entirely via `GlideStepDelay`, not
      Sleep/Pause): 100px ≈ 13 steps ≈ 26-65ms; 240px+ (the clamp point)
      through 1500px all plateau at 30 steps ≈ 60-150ms, since
      `HUMANMOVE_MAX_STEPS` caps SAMPLE COUNT not step size — a long
      move just takes proportionally bigger per-sample jumps, not more
      samples. Conservative upper bound: samples near the eased ends
      often round to the same pixel and get skipped (no delay paid), so
      real elapsed time is normally below this table. Redo this
      arithmetic before retuning these constants — the 2026-07-27
      WindMouse saga got bitten hard by skipping it.
    - **`GlideStepDelay`** (renamed from `WindMouseStepDelay`, body
      unchanged) — still the `QueryPerformanceCounter` busy-wait; still
      the only way to get real sub-tick pacing on this system, used by
      `HumanGlide`'s per-step pacing.
    - **`IdleWander` — added 2026-07-30, REMOVED same day.** Small
      random cursor hops (via `HumanGlide`) during long idle stretches,
      wired into `TrackAndClick`'s stable-and-not-clicking branch via an
      opt-in `idleWanderAfterMs`. Design included a safety mechanism
      (avoid-region re-roll around the tracked block's own search box,
      so wandering couldn't occlude the next search tick) that worked as
      designed, and a timing knob that got tuned down live (20s → 4s to
      actually fire on shorter chop cycles) — but live testing found the
      overall feature just didn't work as intended, so it was ripped out
      completely rather than kept half-working: `IdleWander`/
      `IDLE_WANDER_*` gone from `Act.ahk`, `idleWanderAfterMs`/
      `lastMouseActivityAt` gone from `TrackAndClick`, `micro\
      28-idle-wander.ahk` deleted. Not re-attempting without a clearer
      idea of what specifically felt wrong.
    - **One real click per acquired target is the human baseline**:
      `TrackAndClick`'s `cooldownMs` (the periodic reclick-while-stable
      interval) now defaults to 0 = disabled, not a required opt. A
      person doesn't keep re-clicking a tree they're already chopping;
      `cooldownMs > 0` is now an explicit opt-in for targets that
      genuinely need repeated interaction. Fallout: `lastProgressAt`
      (the stuck-detector reset) had to move off "only resets on a
      click" to "resets on any tick that still sees the target" —
      otherwise a healthy target with reclick disabled would eventually
      trip `progressTimeoutMs` for doing nothing wrong.
    - **`reclickAfterMs` (the not-yet-stable miss-recovery reclick
      delay) accepts `[min, max]` as well as a plain number** — a
      person doesn't wait the exact same beat before re-clicking a
      miss every time. Re-rolled via `NextReclickThreshold()` on every
      new target acquisition and after every reclick, not once per run.
      Woodcutting uses `[50, 300]`; a plain number is still fixed
      (back-compat, e.g. micro 21 still passes one).
    - **Click-point jitter**: every click on a fixed UI asset (bank
      buttons, menu items) was landing the EXACT same pixel every time
      - `FindImage` always returns the identical center for a static
      capture, nothing upstream naturally varies it. `Act.ahk`'s
      `JitterPoint(x, y, jitterPx, &jx, &jy)` is applied in `ClickAt`
      (trailing `jitterPx := -1` param) and `RightClickMenuItem`'s
      right-click, BEFORE the glide - `HumanGlide`'s exact-landing
      guarantee still holds, it just aims at a slightly different spot
      each time.
    - **Made proportional 2026-07-28** (live feedback: jitter should
      scale with target size, e.g. a 45x45 tree block gets ~25% =
      ~11px, not a flat few px): `BlockJitterPx(w, h)` =
      `CLICK_JITTER_PERCENT` (0.25) of `Min(w,h)`, capped at
      `CLICK_JITTER_MAX_PX` (40 - a ceiling only, shouldn't clip any
      real target here). Every composite that knows its target's real
      size computes and passes it: `WaitThenClick` (reads whichever of
      `blockW/blockH` or `w/h` the caller's opts has - covers
      `FindAndClickBlock`/`FindAndClickImage` for free),
      `ClearAllInstances` (image w/h), `TrackAndClick` (blockW/blockH,
      computed once - the tracked block's size is constant for the
      whole run), `PickupAppeared` (imageW/imageH),
      `RightClickMenuItem` (optional blockW/blockH for the right-click
      target, the menu item's own w/h for the follow-up click),
      `DropSlot`/`RunRestockPlan` (`INV_GRID`/`BANK_GRID` cellW/cellH).
      The sentinel `jitterPx = -1` (flat `CLICK_JITTER_MAX_PX`
      fallback) survives for the one real caller with no size concept:
      `TravelToPoint`'s PIN-mode click on an arbitrary marker point.

## File map so far

- `Lib\Core.ahk` — `Pause`, `WaitUntil`, `Say`, `LogLine`,
  `TrimLogOnStart`, `BotStopped`, `GameActive`, `CenterX`/`CenterY`,
  `JoinMsg`, `Opt` (opts unpacker, standard #24), `POLL_MS_DEFAULT`.
- `Lib\Find.ahk` — `SolidBlockBitmap`, `FindFilledBlock`, `HexColor`,
  `RegionAround` (marginPx default 0), `ScreenRegion`, `SearchZone`
  (mode switch, standard #22), `AcquireClosestInBox`,
  `GameZoneRegion`/`GAME_ZONE_*`, `CHAR_X/Y`, `ACQUIRE_PADDING_*`,
  `BANK_DEPOSIT_IMAGE_*`/`DEPOSIT_BOX_IMAGE_*` + their precomputed
  `_REGION` constants (see standards #17/#27/#28), `ColorClose`, `IsColorAt`,
  `IsAnyColorAt`, `FindAnyFilledBlock`, `WatchIndicator`, `BlockAtPoint`
  (marginPx default 0), `ImagePattern`, `FindImage`,
  `WaitForImage`/`WaitForImageGone`, `TakeSnapshot`/`HasChanged`.
- `Lib\Act.ahk` — `HumanGlide`/`HumanMove` + `HUMANMOVE_*` tuning
  globals, `GlideStepDelay` (busy-wait pacing), `RandTri`/`MinJerk`/
  `TremorWeight` (glide math), `JitterPoint`/`BlockJitterPx` +
  `CLICK_JITTER_*` globals (standard #29, micro 27), `ClickAt` (glide,
  then modifiers, then click; async modifier release), `PressKey`,
  `ReleasePendingModifiersNow`, `g_PendingModifierKeys`.
- `Lib\Steps.ahk` — `RightClickMenuItem`, `WaitThenClick` (shared
  engine, standard #24), `FindAndClickBlock`, `FindAndClickImage`
  (both thin wrappers over `WaitThenClick`), `ClearAllInstances`,
  `VerifySlotsAndDrop`, `ClickUntilCondition`, `TrackAndClick` + `class
  TargetLock` (biggest composite, see standards #15/#16), `PickupAppeared`,
  `TravelToPoint` (arrival margin = visible `arriveMarginPx` opt,
  default 0), `DepositAllToBank`, `RunRestockPlan`, `GatherBankLoop`
  (ALL opts-object except `RunRestockPlan`, which is positional
  `(plan, ctrl)` — see standard #13).
- `Lib\Grid.ahk` — `GridSpec`, `GridCorner`, `GridCenter`,
  `GridCellRegion`.
- `Lib\Inv.ahk` — `INV_GRID`, `SlotCenter`/`SlotCorner` (thin Grid
  wrappers), `SlotFull`, `SlotProbe`, `AnySlotEmpty`, `AllSlotsFull`,
  `AllSlotsEmpty`, `DropSlot`, `BANK_GRID`, `BankSlotCenter`.
- `Lib\Bot.ahk` — `InstallBotHarness` (micro 26, standard #23),
  `BindHotkeyHandler`.
- `micro\01`–`26` — ALL confirmed live, see each file's own header for
  what it validates and its LIVE CONFIRM steps. (Old micro 18 was
  written, dropped, and deleted — see standard #12.) Step 2 is complete.
- `micro\27-human-move.ahk` — `HumanMove`/`HumanGlide` validation
  (standard #29). Was `27-wind-move.ahk` (validated `WindMouseMove`)
  until the 2026-07-30 rewrite renamed it in place - same slot, new
  algorithm underneath. NOT yet confirmed live.
- `Tools\` is now empty — both mover demos it ever held
  (`windmouse.ahk`, `humanized-mouse.ahk`) have been promoted into
  `Act.ahk` and deleted, standard #29.
- `Images\deposit-motherlode.png` (80×72, copied from v6, placeholder
  test asset), `li_bank-deposit-box.png` (332×30, user-supplied real
  menu-item asset), `sudoku-slot.png` (72×64, copied from v6, used by
  micro 17), `pay-dirt.png` (72×64, copied from v6, used by micro 19),
  and `deposit-bank.png` (72×72, used by micro 24 for the deposit-all
  button) exist as test images.

## Step 2 complete — all 26 micros confirmed live (2026-07-23)

No micros remain. **Step 3 starts now**: build `Bots\` (autoclicker →
woodcutting → crafting → smithing [own log name — fix the v6
`g_LogName := "crafting"` bug] → seller → sudoku → motherlode2),
simplest-first, motherlode2 last (most surface, all of it micro-proven
by now). Each bot: `InstallBotHarness` (micro 26) for F5/F6/F12/probe/
extra hotkeys, `SearchZone` (micro 25, standard #22) for region config,
`GatherBankLoop` (micro 25) for the gather→bank→repeat bots
(woodcutting/motherlode2/crafting), corner-measured calibration blocks,
zero bare `Pause()`, zero click offsets, zero raw `Send()`.

## Working style reminders (from user feedback this session)

- Ask before assuming a search region — the user wants a *specific*
  known area/marker, not "just search the whole game zone/screen" as a
  lazy default.
- When two params look similar (e.g. `MARGIN_PX` vs `POS_TOL_PX`), explain
  the real distinction rather than assuming redundancy — but also be
  honest when they DO overlap in a specific test's current config.
- When the user says "why isn't X global/consistent," take it seriously —
  several constants (`CHAR_X`, `GAME_ZONE_*`, `ACQUIRE_PADDING_*`) moved
  into Lib specifically because of this kind of pushback.
- Don't build/test things that don't map to a real described scenario
  (e.g. `FindAndClickImage`, the original blind click-then-Esc test) —
  ask what the actual use case is first.
