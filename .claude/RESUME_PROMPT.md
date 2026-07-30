# Starter prompt — paste this as your first message in a new session
# (works for Claude Code or any other coding agent)

Continuing the OSRS automation project (AutoHotkey v2, repo root: this
folder). **Read `PROGRESS.md` first, in full, before touching any code** —
it is the single authoritative resume doc: current build status, every
confirmed calibration constant, and a numbered list of standards/lessons
learned the hard way (each one was a real live-testing correction, not a
style preference — don't re-litigate or "improve" past what's written there
without new evidence). `README.md` gives the folder layout and how to run a
script.

## What this codebase is

A small LEGO-style architecture: `Lib\` (shared primitives + composites) →
`micro\` (one standalone, live-confirmed validator script per Lib
primitive/composite) → `Bots\` (real gameplay loops composed from `Lib\`
calls). `legacy\` holds the previous version of this codebase (frozen, not
touched) as a working fallback — never edit anything under `legacy\`.

## Non-negotiable conventions (all covered in more depth in `PROGRESS.md`)

- `Pause()` (`Lib\Core.ahk`) is the ONLY sleep primitive anywhere — never a
  raw `Sleep()`. It's interruptible (F6 → `g_StopRequested` → throws
  `BotStopped`).
- Corner-measured calibration: a target is `X, Y` (top-left corner) + `W, H`,
  never a hand-typed center or a precomputed `[x1,y1,x2,y2]` array with
  inline arithmetic. Centers are always derived via `CenterX`/`CenterY`.
- Colors are always an array, even for one color: `TARGET_COLORS := [c]`.
- No click-offset compensation constants, ever. A mis-click means re-measure
  the target, not add an offset.
- Every action-performing function takes `preDelayMs`/`postDelayMs` (default
  0), routed through `Pause`. Every script's `EDIT THESE` config block shows
  EVERY tunable, even ones left at their default (0, 100, etc.) — nothing
  hidden behind a silent Lib default.
- `MARGIN_PX`/`POS_TOL_PX`-family values default to 0 everywhere. Only raise
  one after live testing actually shows drift — never as a precaution.
- Detection/action primitives (`Find.ahk`/`Act.ahk`/`Grid.ahk`/`Inv.ahk`) take
  positional args. `Steps.ahk` composites take ONE opts object. Don't mix the
  two styles.
- `SearchZone(opts)` (`Find.ahk`) is how every script builds its search
  region: one `mode` field (`"full"`/`"area"`/`"fixed"`/`"quadrant"`). Write
  ONE object-literal per mode inline at the call site (other modes commented
  out below it) — never conditionally-assigned separate globals (AHK v2's
  "variable never assigned" check is a whole-file static scan, not
  per-branch, so a dead branch's assignment still gets flagged).
- A region built purely from fixed constants (e.g. a bank UI button that
  never moves) is itself a fixed constant — precompute it once in `Find.ahk`
  next to the X/Y/W/H it derives from, don't rebuild it per bot.
- `InstallBotHarness` (`Lib\Bot.ahk`) is the one call every bot uses for its
  F5/F6/F12/probe/extra-hotkey wiring — never hand-roll this.
- Syntax-check without running: `AutoHotkey64.exe /ErrorStdOut /validate
  <path>` — **from PowerShell, not Git Bash** (Git Bash mangles the
  `/validate` switch into a path). Re-run across every `.ahk` file that
  includes a touched `Lib\` file after any Lib edit.

## How to work

1. When asked to add real, new Lib surface (a new kind of search/action/
   composite the project has never had before), build it the same way this
   project always has: write ONE new `micro\NN-name.ahk` validator script
   exercising just that new piece, get it **live-confirmed in-game by the
   user** before writing the next thing or touching a `Bots\` file. Don't
   batch several new primitives and test them all at the end.
2. When asked to build a bot from already-confirmed Lib pieces (the common
   case once Lib is mature), you can move faster — no new micro needed,
   just compose the existing `Lib\` functions in a new `Bots\*.ahk` file
   following the harness/config-visibility conventions above — but still
   get the finished bot live-confirmed end-to-end before considering it done.
3. Before adding a new Lib function, check whether an existing one already
   covers the shape (see `PROGRESS.md` standard #12 for a real instance of a
   composite being written then deleted once this was discovered).
4. Before promoting something to a Lib "global constant," get clear on
   whether it's genuinely fixed (same screen position no matter what/where,
   like a UI button) vs per-script config (varies by location/target, like a
   marker color) — standard #17 covers the exact distinction and the
   corrections that established it. When unsure, ask rather than guess.
5. Diagnose from real evidence, not guesses: read the relevant `logs\
   <name>.log` file before concluding anything about timing or behavior.
6. Update `PROGRESS.md` as you go: add newly-confirmed calibration constants,
   append a new numbered standard for any real correction/lesson (with the
   concrete evidence that produced it, not just the rule), and update the
   file map. Keep it pruned to durable facts — this file is a working
   reference, not an append-only diary.

## Likely next steps

See `PROGRESS.md`'s "Step 3" section for the current bot build order and
which bots remain. Each new bot: `InstallBotHarness` for the F5/F6/F12/probe
wiring, `SearchZone` for region config, `GatherBankLoop` for any
gather→bank→repeat loop, corner-measured calibration block, zero bare
`Pause()`, zero click offsets, zero raw `Send()` (use `PressKey`).
