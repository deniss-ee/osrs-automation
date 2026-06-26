# Prompt: continuing/extending the OSRS gathering automation library

Paste everything below into a new AI coding session to onboard it to this project.

---

I have an OSRS (Old School RuneScape) automation project in AutoHotkey v2, in the folder
`auto gathering`. Read `docs\DOCUMENTATION.md` first — it fully describes the architecture,
every library function, every current script, the folder layout, the coordinate conventions,
and the bug history. Don't start writing code until you've read it.

## Hard rules

1. **Never write a raw `PixelGetColor`, `Click`, `MouseMove`, or `PixelSearch` call directly in
   a script.** Every one of those already has a wrapper in `lib\` (`Colors.ahk`, `Click.ahk`).
   If the exact thing I need doesn't exist yet, add it to the right `lib\` file (not inline in
   the script) so every future script gets it too. **Banking is the same**: deposit and withdraw
   live in `lib\Bank.ahk` (`BankDepositAll` / `BankWithdrawSlot`) — call those from a `BankPhase`,
   passing the script's own settle/failsafe delays; don't re-inline the deposit/withdraw sequence.
2. **Never edit `miner-3.ahk`, `motherlode-miner.ahk`, `smelter-1.ahk`, or their `.ini` files.**
   They're the original scripts, kept only as reference for "what behavior should this
   replicate". `motherlode-miner.ahk`/`.ini` live in `legacy\`; `miner-3.ahk`/`.ini`,
   `smelter-1.ahk`/`.ini`, and `miner-2-member.ini` have been relocated to a sibling `..\backup\`
   folder (not deleted) — read any of them for reference, but all new/changed work happens in
   `lib\`, or in the active scripts under `scripts\` (`auto-miner.ahk`, `auto-smelter.ahk`,
   `auto-fisher.ahk`, `auto-smith.ahk`, `auto-motherlode.ahk`, `auto-fighter.ahk`), or in new
   scripts built the same way and placed in `scripts\`.
3. **Every phase function** (the functions registered via `AddPhase`) must:
   - Start with `if (!RequireOsrsWindowActive()) return GoToPhase(taskRunner, "<same phase>")`.
   - Call `ResetPhaseTimer(taskRunner)` after making genuine progress (a click, a completed
     path) if that phase is allowed to legitimately stay active a long time — otherwise the
     phase's timeout will fire even though it's working correctly.
4. **Any "did this slot/pixel actually change state" check should debounce** with a
   `confirmTicks` value (2–3 typical), using `WaitForPixelColorChange` / `WaitUntilOccupied` /
   `WaitUntilNotOccupied` from `Colors.ahk` — never trust the first different-looking poll, a
   one-frame glitch is enough to cause a false positive.
5. **Inventory/bank slot occupancy is always multi-point**, never a single pixel — calibrate via
   `GetSlotSamplePoints(slot, GetDefaultSlotOffsets())` and `IsAnyPointOccupied`/
   `WaitUntilOccupied`/`WaitUntilNotOccupied`, not a bare `PixelGetColor` compare.
6. **Coordinates the user gives you as "WxH px, position x=,y="** are TOP-LEFT corners, not
   centers. Run them through `Grid.ahk`'s helpers (or model any new preset the same way) — don't
   use them directly as click/sample centers.
7. **Run vs. walk is a plain `.ini` flag** (`[Settings] runMode`), read once at script load into
   a global, used to decide whether `HumanClick` Ctrl-holds. Never add a hotkey toggle or any
   stamina-orb color reading for this — the user explicitly rejected that approach.
8. **Recorded path format**: an array of step `Map`s `{x, y, pause, button, running}`. `pause`
   is the wait AFTER that step's click (not before). The wait before a path's very first click
   is the single global `INITIAL_CLICK_DELAY` in `lib\Paths.ahk`, not a per-path field. Don't
   reinvent a different path shape for a new script.
9. **`ENABLE_HUMANIZATION`** (in `Click.ahk`, default `false`) makes clicks land on the exact
   calibrated pixel with exact delays; set `true` near the top of a script if you want the subtle
   randomized offset/jitter (hard-capped at ±2px / ±100ms either way). Leave whatever value is
   currently in a script alone unless I ask you to change it — don't "helpfully" flip it during an
   unrelated edit.

## Standard process for building a new gathering/processing script

Don't copy an existing script as a starting point. Learn the conventions from `DOCUMENTATION.md`
and from reading the existing scripts in `scripts\`, then write the new script from scratch
following those conventions:

1. Pick whichever existing script's cycle shape is closest to what I'm describing (a fixed-spot
   gathering loop like `auto-miner.ahk`, or a "do one action, wait for inventory to change, bank"
   loop like `auto-smelter.ahk`) and use it as a reference for structure, not as a template to
   duplicate.
2. Add one calibration hotkey per value the script needs, following the existing F1/F2 pattern:
   `MouseGetPos`/`PixelGetColor` → a `Save*` call from `ConfigStore.ahk` → `ShowTipFor`.
3. Build whatever `NewPathRecorder()` instances the script needs, and wire `ToggleRecording`/
   `RecordClick` for them the same way the existing scripts do.
4. Register phases with `AddPhase(runner, name, fn, timeoutMs)` — keep each phase a single
   responsibility (one action + one wait + one transition).
5. Write a `ValidateSetup()` with one `RequireX` line per calibration value.
6. Wire start/stop/clear hotkeys the same way the existing scripts do (whichever F-keys come next
   after the calibration ones — e.g. `auto-smith.ahk` uses F5/F6/F7, `auto-motherlode.ahk` uses
   F7/F8/F9 since it has more calibration hotkeys first — there's no fixed key number, just the
   same start→stop→clear order at the end).
7. Ask me for the exact coordinates/behavior I expect for anything not inferable from the
   existing scripts — don't guess UI positions.

## Testing/safety practices

- After writing or editing any `.ahk` file, syntax-check it:
  `& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut "path\to\file.ahk"`.
  Lib files (no hotkeys) exit on their own — any output means a load error. Files with hotkeys
  stay resident — launch via `System.Diagnostics.Process`, confirm it's still running after ~2s
  with no error output, then kill that process.
- **Never kill an AutoHotkey process you didn't just launch yourself without checking first** —
  it might be the user's own live test session of one of these scripts. If you're not sure,
  check the window title/command line, and when in doubt, leave it running and ask.
- Don't claim a script "works" from a syntax check alone — that only proves it loads. Say
  explicitly that in-game behavior is unverified unless the user has actually tested it.

## Keeping the docs current

If you add a `lib\` function, a new script, or change a convention, update `DOCUMENTATION.md`
to match (new function reference entry, updated tunables list, new entry in the bug history if
you fixed something real). Keep this file (`PROMPT.md`) in sync if you establish a new hard
rule the user gives you.
