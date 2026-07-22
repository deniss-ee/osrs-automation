# v7 rewrite — progress / continuation notes

Read this file first in a new session before touching v7. Full plan lives at
`C:\Users\link\.claude\plans\v7-full-rewrite-parallel-possum.md` — this file
is the fast-resume supplement, not a replacement.

## Where things stand

**Micros 1–17 built and live-confirmed.** Micro 18 (the old
"wait-marker-then-click" M9 two-stage shape) was DROPPED (2026-07-23) —
live testing showed it duplicated micro 11's `FindAndClickBlock` with a
`clickX`/`clickY` pin, which already covers "wait for a marker, click a
different point." The remaining micros (old 19–27) were renumbered down
by one to close the gap — see the table below for the current numbering.
Next up: micro 18 = drop-slot. v6 (repo root) is untouched and still the
working fallback.

Build-order rule in force: Lib is assembled incrementally, ONE function (or
tightly-coupled group) per micro, in lockstep with the micro that exercises
it. Never write a Lib function ahead of its micro. `v7\Lib\v7.ahk` is the
umbrella include — every new file gets one `#Include` line added there.

## Confirmed calibration constants (this user's setup)

Screen: 2560×1440. These live in `v7\Lib\Find.ahk` / `v7\Lib\Inv.ahk` —
do not redefine them per script, reference them.

- `GAME_ZONE_X1/Y1/X2/Y2` = `0, 45, 2499, 1380` (game viewport sub-region,
  not full screen) — `GameZoneRegion()` accessor.
- `CHAR_X/CHAR_Y` = `1249, 712` (character's on-screen center, fixed
  camera/zoom).
- `ACQUIRE_PADDING_SMALL/LARGE` = `64, 128` (ring-expand defaults, M4).
- `INV_GRID` = `GridSpec(2099, 801, 4, 7, 72, 64, 12, 8)` in `Inv.ahk` —
  same numbers v6 measured, reconfirmed live on this setup via micro 13.
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

## File map so far

- `v7\Lib\Core.ahk` — `Pause`, `WaitUntil`, `Say`, `LogLine`,
  `TrimLogOnStart`, `BotStopped`, `GameActive`, `CenterX`/`CenterY`,
  `JoinMsg`.
- `v7\Lib\Find.ahk` — `SolidBlockBitmap`, `FindFilledBlock`, `HexColor`,
  `RegionAround`, `AcquireClosestInBox`, `GameZoneRegion`/`GAME_ZONE_*`,
  `CHAR_X/Y`, `ACQUIRE_PADDING_*`, `ColorClose`, `IsColorAt`,
  `IsAnyColorAt`, `FindAnyFilledBlock`, `BlockAtPoint`, `ImagePattern`,
  `FindImage`.
- `v7\Lib\Act.ahk` — `ClickAt` (async modifier release), `PressKey`,
  `ReleasePendingModifiersNow`, `g_PendingModifierKeys`.
- `v7\Lib\Steps.ahk` — `RightClickMenuItem`, `FindAndClickBlock`,
  `ClearAllInstances`.
- `v7\Lib\Grid.ahk` — `GridSpec`, `GridCorner`, `GridCenter`,
  `GridCellRegion`.
- `v7\Lib\Inv.ahk` — `INV_GRID`, `SlotCenter`/`SlotCorner` (thin Grid
  wrappers), `SlotFull`, `SlotProbe`, `AnySlotEmpty`, `AllSlotsFull`,
  `AllSlotsEmpty`.
- `v7\micro\01`–`17` — all confirmed live, see each file's own header for
  what it validates and its LIVE CONFIRM steps. (Old micro 18 was
  written, dropped, and deleted — see standard #12.)
- `v7\Images\deposit-motherlode.png` (80×72, copied from v6, placeholder
  test asset), `li_bank-deposit-box.png` (332×30, user-supplied real
  menu-item asset), and `sudoku-slot.png` (72×64, copied from v6, used by
  micro 17) exist as test images.

## Remaining Step 2 micro list (not yet built) — renumbered 2026-07-23

| # | Micro | Validates |
|---|-------|-----------|
| 18 | drop-slot | `DropSlot` |
| 19 | verify-slots | `VerifySlotsAndDrop` |
| 20 | click-until-condition | `ClickUntilCondition` + `&neededRetry` |
| 21 | track-and-click | `TrackAndClick`+`TargetLock` |
| 22 | pickup-appeared | `PickupAppeared` (offsets removed) |
| 23 | travel-to-point | `TravelToPoint` |
| 24 | deposit-all | `DepositAllToBank` + `RunRestockPlan` |
| 25 | gather-bank-loop | `GatherBankLoop` |
| 26 | bot-harness | `Bot.ahk` (shared F5/F6/F12 run/stop harness) |

Then **Step 3**: build `v7\Bots\` (autoclicker → woodcutting → crafting →
smithing → seller → sudoku → motherlode2), only after all 26 micros are
confirmed.

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
