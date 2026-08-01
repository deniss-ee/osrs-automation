# Starter prompt — paste this as your first message to make Claude do this audit

Audit every action-performing function in `Lib\*.ahk` (`Act.ahk`, `Steps.ahk`, `Find.ahk`, `Inv.ahk`) and make sure each one exposes its own pre-delay and post-delay as optional parameters — never as a bare `Pause()` call sitting in a `Bots\*.ahk` file outside any function.

**Why:** this was an explicit rule from early in the project ("all the waits, delays, settlers should be a parameter of a function") that's been only partially followed. `ClickUntilCondition` (`Lib\Steps.ahk`) already does this correctly via its `firstSettleMs` param. `DepositAllToBank` does not — `Bots\smithing.ahk` needed a settle after banking and, in the absence of a parameter for it, got a standalone `Pause(DEPOSIT_SETTLE_MS)` added directly in the bot file after the `DepositAllToBank` call. That's the anti-pattern to eliminate: it's less discoverable, easy to forget to add per-bot, and breaks the "the Lib function owns its own timing" contract every other composite in this file follows.

**Scope — go function by function through `Lib\Steps.ahk` first (it's the composite-step file, most likely to need this), then `Lib\Act.ahk`/`Lib\Find.ahk`/`Lib\Inv.ahk`:**
- `FindAndClickBlock`, `FindAndClickImage` — check for pre-click and post-click settle params.
- `DepositAllToBank` — needs at least a post-deposit settle param (this is the one confirmed missing, per the smithing.ahk incident above).
- `RunRestockPlan` — check whether a per-click or post-plan settle is needed (some UIs need a beat between rapid same-slot clicks).
- `ClickUntilCondition` — already has `firstSettleMs`; confirm it's the right shape and doesn't need a post-condition settle too.
- `TravelToPoint` — check for a post-arrival settle before the caller's next step.
- Anything else in `Lib\Act.ahk`/`Lib\Find.ahk`/`Lib\Inv.ahk` that clicks, sends a key, or otherwise performs an action.

**How to do it (match existing style):**
- Optional param, default `0` (no-op), e.g. `preSettleMs := 0`, `postSettleMs := 0` — same pattern as `ClickUntilCondition`'s `firstSettleMs := opts.HasOwnProp("firstSettleMs") ? opts.firstSettleMs : 0`.
- Use the existing `Pause()` (`Lib\Core.ahk`) for the actual sleep — never `Sleep()` directly, `Pause` is "the ONLY sleep function in v6" (interruptible, checks `g_StopRequested`).
- Log via `Say()`/`LogLine()` when a non-zero settle actually fires, same style as `ClickUntilCondition`'s `"settling Nms before checking X"` line.
- Update each function's doc comment (the `; opts:` block above it) to document the new param.

**Then, once `Lib\Steps.ahk` exposes these params:**
- Go back through `Bots\crafting.ahk` and `Bots\smithing.ahk` and replace the standalone `Pause(DEPOSIT_SETTLE_MS)` call after `RunRestockPlan`/`DepositAllToBank` with the new function parameter instead (e.g. `DepositAllToBank({ ..., postDepositSettleMs: DEPOSIT_SETTLE_MS })`), removing the bare `Pause()` call from the bot file.
- Check `Bots\motherlode2.ahk` and `Bots\woodcutting.ahk` too — they may have their own standalone `Pause()` calls between steps that belong on a function parameter instead (e.g. `SACK_CLICK_SETTLE_MS`, `HOPPER_CLICK_SETTLE_MS` — check whether those already go through a param like `ClickUntilCondition`'s `firstSettleMs`, or are bare `Pause()` calls that need the same fix).

**Don't:**
- Don't add pre/post settle params to functions that don't need them yet (no speculative plumbing) — only where a real bot currently needs one, or where a bare `Pause()` already exists next to a Lib-function call and should be absorbed into it.
- Don't change default behavior — every new param must default to `0`/off so existing callers are unaffected unless they opt in.
