# Starter prompt — paste this as your first message in a new session

I'm resuming work on my OSRS AutoHotkey v2 automation project at this repo
root. Read this whole prompt first, then read `PROGRESS.md` in full before
touching any code — it is the single authoritative resume doc.

## Repo layout

- `Lib\`, `micro\`, `Bots\`, `Tools\`, `Images\`, `logs\` live at the repo
  root — this is v8, promoted here 2026-08-01. All 12 micros are
  live-confirmed. `Bots\woodcutting.ahk` is the first real bot, built and
  **live-confirmed working** by me.

## Where things stand right now

All 12 v8 micros are live-confirmed against a real RuneLite session. Four
real AHK v2 bugs were found and fixed during that pass (all invisible to
`/validate`, only surfacing live) — full detail in `PROGRESS.md`, but the
durable lesson: **AHK v2 variable names are case-insensitive** (a local can
silently shadow a global or even a Lib function of the same name), and
**calling a closure stored on an object via dot-syntax (`obj.prop()`)
implicitly passes the object as a hidden first argument** — always extract
to a local first (`fn := obj.prop`, then `fn()`).

Building `woodcutting.ahk` after that grew the Lib substantially, all under
live iterative tuning with me (I'd test, report back, you'd adjust, repeat).
That's exactly how this project has always worked, but it means the growth
below happened faster than the project's usual "one micro per new
primitive" discipline. **This is the important part: my immediate ask for
this session is an audit + standardization pass over everything listed
below — NOT new features** — before any other bot gets built on this Lib.

`PROGRESS.md`'s "Lib growth" section has the full list with file/line
detail; in short: `DepositAllToBank` gained independent per-click
ctrl (`markerCtrl`/`depositCtrl`) and a settle delay before the
deposit-button search; `TrackAndClick` gained a pre-acquisition pause
(`acquireDelayChance`/`acquireDelayMs`); a brand-new movement primitive
`WanderNear` (`Act.ahk`) does idle cursor wandering (circular loops + long
hops, full-screen); `HumanGlide`/`HumanMove` gained optional pacing/step-count
overrides so `WanderNear`'s long legs stay smooth; and `WaitUntil` — the
single most-used primitive in the whole Lib — gained an opt-in wander hook,
threaded through `WaitForTarget`/`FindAndClick`/`DepositAllToBank` (all
three of its waits). A `Tools\` folder was also added:
`record-movement.ahk`/`analyze-movement.ahk`, a real mouse-movement
recorder + statistics analyzer, used once to calibrate `WanderNear`'s speed
against my own real recorded movement.

**Known inconsistency to fix in the audit:** `TrackAndClick` calls its
wander opts `idleWanderChance`/`idleWanderCheckMs`/`idleWanderDurationMs`;
`DepositAllToBank` calls the same concept `wanderChance`/`wanderCheckMs`/
`wanderDurationMs` (no `idle` prefix). Pick one shape — probably a single
shared `wander: {chance, checkMs, durationMs}` opts object every wait-aware
composite accepts, instead of each one redeclaring its own trio.

**Other open items** (all in `PROGRESS.md`, don't re-discover from scratch):
`BANK_GRID` rows beyond row 1 are still unmeasured; micro 08's menu-row
image asset (`li_bank-deposit-box.png`) never matched live even after
several fix attempts — needs a fresh recapture before `RightClickMenuItem`
is used in a real bot; `WanderNear` has no dedicated micro (it was built
live inside the bot, skipping the usual per-primitive live-confirm step) —
worth deciding whether it needs one retroactively.

## What this codebase is

A small LEGO-style architecture: `Lib\` (shared primitives + composites) →
`micro\` (one standalone, live-confirmed validator script per Lib
primitive/composite) → `Bots\` (real gameplay loops composed from `Lib\`
calls) → `Tools\` (one-off calibration/diagnostic scripts, not part of the
Lib chain). `archive\` holds every previous version (frozen, never edit).

## Non-negotiable conventions (all covered in more depth in `PROGRESS.md`)

- `Pause()` (`Lib\Core.ahk`) is the ONLY sleep primitive anywhere — never a
  raw `Sleep()`. It's interruptible (F6 → `g_StopRequested` → throws
  `BotStopped`).
- `ClickTarget(x, y, w, h)`'s x/y is a CENTER, not a corner — every click in
  the project is built from one, and jitter is mathematically bounded
  inside that cell. Corner-measured calibration inputs get converted to
  center once (`CenterX`/`CenterY` or a composite's own find-result).
- Colors are always an array, even for one color: `TARGET_COLORS := [c]`.
- No click-offset compensation constants, ever. A mis-click means
  re-measure the target, not add an offset.
- Every action-performing function takes `preDelayMs`/`postDelayMs`
  (default 0). Every script's `EDIT THESE` config block shows EVERY
  tunable, even ones left at their default — nothing hidden.
- `MARGIN_PX`/`POS_TOL_PX`-family values default to 0 everywhere. Only
  raise one after live testing actually shows drift.
- Detection/action primitives (`Find.ahk`/`Act.ahk`/`Grid.ahk`/`Inv.ahk`)
  take positional args. `Steps.ahk` composites take ONE opts object.
- `RandTri(lo, hi)` (`Act.ahk`) ALWAYS returns a float in AHK v2 (its `/2`
  averaging), even from integer bounds — `Round()` the result before
  feeding it anywhere that requires a strict integer (a real bug this
  session: an un-rounded `RandTri` result reached `GlideStepDelay`'s `//`
  floor-division operator and crashed).
- `InstallBotHarness` (`Lib\Bot.ahk`) is the one call every bot uses for
  its F5/F6/F12/probe/extra-hotkey wiring — never hand-roll this.
- Syntax-check without running: `AutoHotkey64.exe /ErrorStdOut /validate
  <path>` — **from PowerShell, not Git Bash**. Re-run across every
  `micro\`/`Bots\`/`Tools\` file after any `Lib\` edit (they all share the
  same `#Include` chain, so a Lib syntax error shows up everywhere).
  Remember: `/validate` cannot catch case-insensitive name collisions or
  dot-call implicit-`this` bugs — those only surface live.

## How to work

1. When asked to add real, new Lib surface, the project's normal discipline
   is: write ONE new `micro\NN-name.ahk` validator script exercising just
   that piece, get it live-confirmed in-game before writing the next thing.
   (This slipped somewhat for `WanderNear` this session under live bot
   iteration — the audit should decide whether to backfill a micro for it.)
2. When composing a bot from already-confirmed Lib pieces, you can move
   faster — no new micro needed, just compose existing `Lib\` calls in a
   new `Bots\*.ahk` file — but still get the finished bot live-confirmed
   end-to-end.
3. Before adding a new Lib function, check whether an existing one already
   covers the shape.
4. Diagnose from real evidence, not guesses: read the relevant `logs\
   <name>.log` file before concluding anything about timing or behavior.
5. When I report something is still wrong after a fix, don't just nudge the
   same knob again — re-examine the actual mechanism. Most real bugs this
   session (the `WanderNear` geometry bug, the `RandTri` float bug, the
   `CONFIRM_EMPTY_SLOT` false-full read) were found by reading the log
   evidence carefully, not by guessing.
6. Update `PROGRESS.md` as you go — keep it a working reference, not an
   append-only diary. Prune stale content when superseding it.

## My working style / prior feedback (apply these)

- I want real fixes backed by evidence (log lines, actual computed numbers),
  not guesses dressed up as confidence.
- When I give quick iterative feedback ("still slow," "make it X"), just
  apply the change and report back concisely — don't ask permission for
  every small tuning nudge, but DO flag clearly when a change touches
  something load-bearing/shared (a core primitive like `WaitUntil`,
  `HumanGlide`) versus something scoped to one bot's config.
- Confirm destructive/irreversible actions and genuinely large architectural
  choices before doing them — this session that meant checking with me on
  the `DepositAllToBank` ctrl-split approach, how far to wire the wander
  hook into `WaitUntil`, and what the movement-recording tool should
  capture, before building any of them. Small tuning values don't need this.
- Always re-validate the whole tree (`/validate` on every `micro\`/`Bots\`/
  `Tools\` file) after any `Lib\` change, and tell me which already-confirmed
  micros are worth re-checking live given what just changed.
