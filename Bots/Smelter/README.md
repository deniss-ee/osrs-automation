# Smelter

## Overview

Smelts ore into bars at a furnace: walks to a calibrated furnace marker, opens the "Smelt X" dialog, confirms it with space, waits for the ore in the tracked inventory slot to turn into a bar, then walks to the bank, deposits all bars, withdraws a fresh batch of ore for the next cycle, and returns to the furnace. Runs indefinitely until stopped or a timeout/detection failure trips the engine.

**Start assumption**: F5 is pressed with the character standing where the furnace marker and bank marker are both reachable by a single click each (same map area as Firemaking/Smithing use), and with the configured withdraw-slot ore(s) already stocked in the bank. The very first cycle does not require the inventory to already contain ore — `goToFurnace` will walk to the furnace and open the dialog regardless; ore only needs to be present for the smelt itself to actually produce anything (see Known Risks for what happens if it's empty).

**Required calibration — the two-variant `.ini` pattern**: Smelter is one `smelter.ahk` code file driving two different metals via two separate config files, `Config/smelter-gold.ini` and `Config/smelter-mithril.ini`. Both exist in the repo and were confirmed present. **The `.ahk` does not pick a variant at runtime** — `iniPath` is a hardcoded literal at `Bots/Smelter/smelter.ahk:332`:

```
iniPath := A_ScriptDir "\..\..\Config\smelter-gold.ini"
```

To run the mithril variant, this line must be hand-edited to point at `smelter-mithril.ini` (or the two `.ini`s swapped/copied) before launching — there is no CLI flag, environment variable, or in-game selection. Whichever `.ini` this line points to determines the ore/bar recipe end-to-end (indicator slot, withdraw plan, smelt/bank timeouts).

Within whichever variant is active, `SlotSignatureGate.Calibrate()` must run **once per smelt cycle**, and only ever fires automatically inside `SmeltPhase.Run()` — right after pressing space to confirm the dialog (see State Machine below for the exact ordering and a timing risk in that sequence). No manual calibration step is needed by an operator; it re-calibrates every cycle via the `keyPressed` scratch-flag reset in `DepositAndWithdrawPhase`.

## Files

- Entry point: `Bots/Smelter/smelter.ahk`
- Configs: `Config/smelter-gold.ini`, `Config/smelter-mithril.ini` (same code, different calibration/withdraw-plan — see Config Reference)
- Log: `logs/auto-smelter-v4-debug.log`
- Images used: `Images/craft-marker-1.png` (smelt dialog anchor, shared with Firemaking), `Images/deposit-default.png` (bank-open / deposit-all anchor)

## State Machine

`goToFurnace -> smelt -> goToBank -> depositAndWithdraw -> goToFurnace`

1. **`goToFurnace`** (`GoToFurnacePhase`, bot-specific) — verifies the magenta furnace marker (`ColorSearch.FindFilledBlock` against `furnaceMarkerColor`/`furnaceMarkerW/H` at `furnaceMarkerX/Y` ± `furnaceMarkerSearchPaddingPx`), re-clicking every `furnaceMarkerReclickCooldownMs` until found or `furnaceMarkerWaitTimeoutMs` elapses (clean `ctx.engine.Stop(...)` on timeout — never an infinite loop). Once found, clicks it once (latched via `furnaceMarkerClicked`), then waits on `craftAnchor.WaitFor(...)` (an `ImageAnchor` over `craft-marker-1.png`) for the "Smelt X" dialog, up to `craftMarkerWaitTimeoutMs`. On success, hands off to `smelt`.

2. **`smelt`** (`SmeltPhase`, bot-specific — the one phase worth deep documentation here):
   - This phase does NOT use the shared `PressAndWaitEmptyPhase` (see `ARCHITECTURE.md`'s Telemetry/Shared-phases sections for why in general) — because ore→bar never empties the indicator slot's background the way logs→ash or bar→nothing does. A bar occupies the slot's pixels exactly the way ore did, so `Inventory.IsEmpty()`/`SlotGate`+`NotGate` can never observe "done."
   - Instead it uses **`SlotSignatureGate`** (`Detection/Telemetry.ahk`), a baseline-snapshot-then-diff gate: `Calibrate()` samples 4 fixed offsets inside the tracked slot (`SlotSampling.DefaultOffsets()`: center + 3 inset points) and stores them as `this._baseline`. `IsSet()` re-samples the same 4 points and returns true the instant **any** sampled point no longer color-matches (within `colorTolerance`) its own baseline value — i.e., "this slot's contents changed," not "this slot is empty."
   - **Exact sequence in `Run(ctx)` on first entry to a fresh smelt** (`Bots/Smelter/smelter.ahk:149-164`):
     1. `this._keyAction.Press("space")` — confirms the dialog immediately.
     2. `ctx.waiter.After(ctx.timing, this._spaceSettleKey)` — sleeps `spacePressSettleMs` (100ms in both `.ini`s, no jitter since Humanizer is disabled).
     3. `this._signatureGate.Calibrate()` — **only now** takes the baseline snapshot, i.e. ~100ms after space was already pressed and the client already told the game to start smelting.
     4. `ctx.Set("keyPressed", true)` and return `"smelt"` (stay).
   - On every subsequent tick (once `keyPressed` is true), it just checks `this._signatureGate.IsSet()`; once true, logs and transitions to `goToBank`.
   - **Timing risk found**: the code comment at `smelter.ahk:156-158` claims calibration happens "while ore is still visible in the slot, right after confirming the dialog" — but the actual call order is Press → sleep(spacePressSettleMs) → Calibrate, i.e. the settle delay runs **before** calibration, not after. If the game's ore→bar sprite transition begins within that 100ms window (plausible — server tick + client animation could easily land inside 100ms), `Calibrate()` would snapshot a partially- or fully-transformed bar as the "baseline," not ore. Consequences: (a) if the transform is already complete by calibration time, `IsSet()` may never see a further color change for that cycle (the slot could keep flickering between bar-sprite variants that all differ from a "bar" baseline by less than `colorTolerance`, causing a false-negative and a timeout-driven stop) — or (b) `IsSet()` could immediately return true on the very next tick against a still-settling animation, before the actual final bar is present, causing a premature `goToBank` transition mid-smelt-queue. This has apparently not caused a live failure yet (`CURRENT_STATE.md` marks Smelter as live-verified across multiple cycles), but it is a real ordering hazard baked into the current code, not just a comment inaccuracy — see Bugs Found This Audit.

3. **`goToBank`** (shared `GoToBankPhase` from `Core/SharedPhases.ahk`) — verifies/clicks the blue bank marker (`bankMarkerX/Y/W/H/Color`), waits for `deposit-default.png` (`bankOpenAnchor`) up to `bankOpenWaitTimeoutMs`, then hands off to `"depositAndWithdraw"` (the `nextPhaseName` this bot wires in, per `ARCHITECTURE.md` — Firemaking wires the same class to `"withdrawLogs"` instead). See `ARCHITECTURE.md` for the class's full generic behavior; nothing about it is Smelter-specific.

4. **`depositAndWithdraw`** (`DepositAndWithdrawPhase`, bot-specific):
   - **Pre-step (the extra step vs. a plain withdraw-only phase)**: re-finds `deposit-default.png` via `bankOpenAnchor.WaitFor(...)` and clicks its own found center directly as "deposit all" (latched via `depositClicked`). Unlike Firemaking, where this same image is purely a detection signal for "the bank is open," Smelter (and Smithing) click it a second time here as the actual deposit-all button.
   - **Withdraw-plan loop**: steps through an ordered array of `{slotIndex, clicks}` built from the `.ini`'s `withdrawSlotCount` + `withdrawSlot<i>Index`/`withdrawSlot<i>Clicks` keys (see Config Reference). For each entry, calls `Bank.WithdrawSlot(slotIndex, &x, &y)` (pure coordinate math) then `ctx.clicker.ClickSettled(ctx, x, y, runMode)`, repeating `clicks` times with a `withdrawClickIntervalMs` cooldown between repeats (`withdrawClicksDone`/`withdrawLastClickTime` scratch state), then advances to the next plan entry.
   - Once the plan is exhausted, applies a one-time `postWithdrawSettle` delay, logs completion, resets **every** per-cycle scratch flag (furnace-marker wait/click state, `keyPressed`, bank-marker wait/click state, deposit/withdraw state) back to their initial values, calls `ResetForNewCycle()` on every phase in `nextCyclePhases` (`[goToFurnace, smelt, goToBank, depositAndWithdraw]` itself pushed at wiring time), and returns `"goToFurnace"` to start the next cycle.

## Config Reference

All values live under `[Tunables]` unless noted; `[Settings]` holds only `runMode`. Columns marked "same" are byte-identical between the two shipped `.ini` files; "DIFFERS" values are called out explicitly.

| Key | Gold | Mithril | Same/Differs |
|---|---|---|---|
| `runnerTickMs` | 50 | 50 | same |
| `phaseTimeoutFurnace` | 180000 | 180000 | same |
| `phaseTimeoutBank` | 60000 | 60000 | same |
| `colorTolerance` | 20 | 20 | same |
| `furnaceMarkerX/Y/W/H/Color/Tolerance` | 426/967/35/35/0xFF00FF/0 | identical | same |
| `furnaceMarkerSearchPaddingPx` | 10 | 10 | same |
| `furnaceMarkerReclickCooldownMs` | 6000 | 6000 | same |
| `furnaceMarkerWaitTimeoutMs` | 30000 | 30000 | same |
| `craftMarkerAnchorX/Y` | 929/1081 | 929/1081 | same |
| `craftMarkerImageW/H` | 70/60 | 70/60 | same |
| `craftMarkerSearchPaddingPx` | 10 | 10 | same |
| `craftMarkerWaitTimeoutMs` | 15000 | 15000 | same |
| `craftMarkerPollMs` | 100 | 100 | same |
| `spacePressSettleMs` | 100 | 100 | same |
| **`smeltIndicatorSlot`** | **28** | **25** | **DIFFERS** — the tracked slot differs because the two metals' withdraw plans fill the inventory in different slot patterns (see below); this must point at whichever slot is filled *last* by that variant's withdraw plan, so the ore-to-bar transform in that slot is the last one to finish smelting this batch |
| `bankMarkerX/Y/W/H/Color/Tolerance` | 1774/405/41/41/0x0000FF/0 | identical | same |
| `bankMarkerSearchPaddingPx` | 10 | 10 | same |
| `bankMarkerReclickCooldownMs` | 6000 | 6000 | same |
| `bankMarkerWaitTimeoutMs` | 30000 | 30000 | same |
| `bankOpenAnchorX/Y` | 1327/963 | 1327/963 | same |
| `bankOpenImageW/H` | 72/72 | 72/72 | same |
| `bankOpenSearchPaddingPx` | 10 | 10 | same |
| `bankOpenWaitTimeoutMs` | 15000 | 15000 | same |
| `bankOpenPollMs` | 100 | 100 | same |
| `bankSlotFirstX/Y` | 625/203 | 625/203 | same |
| `bankSlotPitchX/W/H` | 96/72/64 | 96/72/64 | same |
| **`withdrawSlotCount`** | **1** | **2** | **DIFFERS** — gold needs only one ore type withdrawn per cycle; mithril needs two (see below) |
| `withdrawSlot1Index` | 3 | 1 | DIFFERS |
| `withdrawSlot1Clicks` | 1 | 4 | DIFFERS |
| `withdrawSlot2Index` | 2 | 2 | present in both files but **only meaningful for mithril** — gold's `withdrawSlotCount=1` means its `withdrawSlot2*` keys are parsed but never consulted by the wiring loop (`loop botConfig.Get("withdrawSlotCount")` only iterates once for gold) |
| `withdrawSlot2Clicks` | 1 | 1 | present in both, only used by mithril |
| `postWithdrawSettleDelayMs` | 100 | 100 | same |
| `withdrawClickIntervalMs` | 100 | 100 | same |
| `clickSettleMs` | 100 | 100 | same |
| `clickSettleJitterPercent` | 0 | 0 | same |
| `ctrlHoldSettleMs` | 100 | 100 | same |
| `runMode` (`[Settings]`) | 1 | 1 | same |

**Withdraw-plan interpretation (multi-ore-type recipes)**: gold bars in OSRS smelt from gold ore alone — one ore type, matching gold's single-slot plan (`withdrawSlot1Index=3`, 1 click, i.e. withdraw-5 or withdraw-all from bank slot 3, no second ore). Mithril bars require **mithril ore + coal**, and mithril's plan reflects exactly that: slot 1 clicked 4 times (almost certainly coal, since standard mithril smelting needs multiple coal per ore — the higher click count matches "withdraw more of the coal stack") and slot 2 clicked once (the mithril ore itself). **The bot's code has no awareness of ore chemistry** — it doesn't know "mithril needs coal" as a concept; the `.ini`'s withdraw-plan array is simply configured with the right slot indices/click counts to withdraw the correct real-world quantities of whichever items happen to sit in those bank slots. This is precisely the "one code, N `.ini`s" design working as intended: the recipe logic lives entirely in config data, not in `smelter.ahk`.

## Known Risks & Edge Cases

**Ore runs out mid-cycle (indicator slot never changes)** → `SmeltPhase.IsSet()` polls forever with no upper bound on "no change detected" beyond the engine's blunt `phaseTimeoutFurnace` (180000ms) → the phase silently waits the full 3 minutes before the *engine* (not `SmeltPhase` itself) force-stops via `FailSafe.HasPhaseTimedOut()`. There is no dedicated "ore exhausted" detection — if the smelt dialog was confirmed but the player actually had 0 of the required ore (e.g. coal ran out mid-inventory but mithril ore didn't, or vice versa for a partial fail), the game would likely produce fewer bars than expected or not smelt the tracked slot at all, and this bot has no way to distinguish that from "still smelting normally" until the 3-minute engine timeout fires.

**Calibration-timing hazard (see State Machine `smelt` section)** → `Calibrate()` runs ~100ms (`spacePressSettleMs`) *after* `Press("space")`, not before/at the same instant. If the client's ore→bar animation for the tracked slot starts within that window, the baseline captures a non-ore state → **Risk**: either a false-negative (the true final bar-sprite variant never differs enough from the accidentally-mid-transform baseline, `IsSet()` never fires, 3-minute timeout stop) or a false-positive (bar not actually finished yet, but a transient animation frame differed enough from baseline to trip `IsSet()` early, causing `goToBank` to fire while the furnace is still mid-batch — no functional break since the bot just walks to the bank regardless of remaining ore, but it would abandon un-smelted ore in the inventory for that cycle, silently reducing bars-per-trip).

**Bar-selection dialog (multi-recipe ores)** → the phase only waits for `craft-marker-1.png` (a generic "smelt X" dialog anchor, shared verbatim with Firemaking's own crafting dialog image) and then blindly presses space. **It never clicks a specific bar-type icon.** In real OSRS, ores capable of producing more than one bar type (this doesn't apply to mithril/gold, which are single-recipe, but would apply if a future variant used an ore like iron, which the base game doesn't gate behind a menu either — practically all current single-bar-per-ore recipes are safe) don't currently present a menu; this is a non-issue for gold/mithril specifically, but is a real gap that must be addressed before adding any variant for an ore that DOES open a bar-choice interface (there is no such recipe in vanilla OSRS today, but a future re-skin, private server, or misconfigured furnace could still surface one) — **the current code has no click step for a bar-selection prompt at all**, so if one ever appeared, space would either dismiss the wrong option or do nothing, and the bot would hang waiting on `SlotSignatureGate` against ore that was never actually queued to smelt.

**Furnace occupied by another player** → `GoToFurnacePhase` only checks for the magenta *marker*, not furnace availability. If another player's smelting animation blocks the click target or the "Smelt X" dialog fails to open because the furnace is mid-use by someone else, `craftAnchor.WaitFor(...)` simply times out (`craftMarkerWaitTimeoutMs=15000`) and the engine stops cleanly — no retry, no queueing behavior. This is safe (no false progress) but requires manual restart.

**Bank deposit-all failing / interface not fully open** → `depositAndWithdraw`'s pre-step re-runs `bankOpenAnchor.WaitFor(...)` (the same `deposit-default.png` anchor `goToBank` already confirmed) before clicking it as deposit-all. If the bank interface closed between phases (e.g. player bumped, client lag) this second wait re-detects it — but if `deposit-default.png` matches a stale leftover render (e.g. the image is still on screen from a closing animation) the click could land on a half-closed interface. No verification exists that the deposit actually succeeded (e.g. checking the tracked slot went empty afterward) — the code proceeds straight into the withdraw loop regardless.

**Withdraw-plan slot mismatch after bank layout changes** → `withdrawSlot1Index`/`withdrawSlot2Index` are raw bank-slot positions (`Bank.WithdrawSlot` is pure index-to-coordinate math with zero content verification). If a player's bank tab layout shifts (item moved, sold, tab reorganized), the bot will click whatever now occupies that slot index with no safety check — could withdraw the wrong item entirely and never notice, since nothing validates slot contents before or after clicking.

**`withdrawSlot2*` keys present-but-inert in gold's `.ini`** → not a bug (confirmed harmless, since `withdrawSlotCount=1` means the wiring loop at `smelter.ahk:388-391` never reads index 2), but worth flagging for anyone hand-editing `smelter-gold.ini`: bumping `withdrawSlotCount` to 2 without also correcting `withdrawSlot2Index`/`Clicks` for gold's actual second-ore-if-any would silently activate stale/copy-pasted mithril-shaped values.

## Anti-Ban / Human-Like Behavior Notes

- `Humanizer(false)` — constructed disabled in both variants (`smelter.ahk:337`), same as every other bot in the framework. `Humanizer.Offset` (spatial click jitter) and `Humanizer.Jitter` (delay jitter) are both no-ops while disabled — clicks land exactly on computed centers, delays are exact `baseMs` values with no randomization.
- `clickSettleJitterPercent=0` in both `.ini`s — even if `Humanizer` were re-enabled, this specific bot's configured jitter percent is 0, so it would still need a nonzero value set before jitter would do anything.
- `runMode=1` in both `.ini`s — every click is wrapped in `Send("{Ctrl down}")`/`{Ctrl up}` (force-attack/force-use style modifier), held for `ctrlHoldSettleMs` (100ms, fixed) before release.
- Poll intervals (`craftMarkerPollMs`, `bankOpenPollMs`, engine `runnerTickMs`) are fixed values, not randomized — consistent with the rest of the framework's current stance (jitter plumbing exists but is deliberately inert everywhere, per `ARCHITECTURE.md`).
- No randomization of click order, timing distribution, or idle/away behavior exists in this bot specifically, nor anywhere else in the framework at present.

## Bugs Found This Audit

1. **`Bots/Smelter/smelter.ahk:153-159`** — comment claims `Calibrate()` runs "while ore is still visible in the slot, right after confirming the dialog," but the actual sequence is `Press("space")` → `ctx.waiter.After(...)` (100ms sleep) → `Calibrate()`. The sleep runs *before* calibration, not after. This is a real ordering hazard (see Known Risks) even though it hasn't caused an observed live failure — the comment describes the intended behavior, not the coded order.
2. **`iniPath` hardcoded to `smelter-gold.ini`** (`Bots/Smelter/smelter.ahk:332`) — the two-variant design described in `ARCHITECTURE.md`/`CURRENT_STATE.md` requires a source edit to switch metals; there is no runtime selection mechanism (env var, command-line arg, or config flag). Not a functional bug (both variants do work when pointed at), but worth flagging since it's easy for a future agent to edit the wrong copy or forget which variant is "live" in the committed `.ahk`.
3. **No post-deposit verification** — `DepositAndWithdrawPhase`'s deposit-all click (`smelter.ahk:213`) has no follow-up check that the deposit actually cleared the inventory before proceeding to withdraw. Functionally harmless in the common case (deposit-all is reliable), but means a failed/partial deposit is silently invisible to the bot.
4. **No ore-exhaustion-specific detection** — confirmed by reading `SmeltPhase.Run` in full: the only way "no more ore" is ever discovered is the blunt 3-minute `phaseTimeoutFurnace` engine-level stop. There's no faster, more specific check (e.g., verifying the withdrawn-ore count against clicks-per-cycle, or watching for a "not enough X" game message).

## Future Agent Development Roadmap

- **Fix the calibration ordering** (`smelter.ahk:154-159`): move `this._signatureGate.Calibrate()` to fire immediately after `Press("space")`, before `ctx.waiter.After(...)`, so the baseline snapshot is taken at the earliest possible moment post-confirm rather than after a 100ms window the game could act within. Verify live afterward (per this framework's stated verification methodology — load-check then F5 then log review, not just a read-through) since this shifts a timing-sensitive gate.
- **Consider making `iniPath` selectable** (CLI arg, env var, or a small launcher wrapper) rather than a hardcoded literal, if a third ore variant is added — three or more hardcoded copies of `smelter.ahk` differing only in one line is a maintenance smell worth resolving before it happens again.
- **Add a third ore-type variant**: following the existing pattern exactly — copy `smelter-mithril.ini` to e.g. `smelter-steel.ini`, recalibrate `smeltIndicatorSlot` (last slot filled by that variant's withdraw plan), `furnaceMarkerX/Y` if the furnace differs, and the withdraw plan's slot indices/click counts for iron ore + coal (steel's real recipe). No `.ahk` code changes needed unless the smelting dialog itself behaves differently (e.g. a bar-selection menu — see below).
- **If a future ore/recipe needs a bar-selection dialog** (not needed for gold/mithril today, but flagged as a gap): `GoToFurnacePhase`/`SmeltPhase` would need a new click step between "smelt dialog visible" and "press space" — likely a new `StaticAnchor`/`ImageAnchor` for the specific bar-type icon, clicked once before the existing space-press logic. This is a real hole in the current design's generality, not just a hypothetical — document clearly in that variant's section if built.
- **Add a lightweight ore-exhaustion check**: e.g., track expected total smelt time from the withdraw-plan's total ore count and compare against a per-cycle expected-duration budget shorter than the blunt 180-second `phaseTimeoutFurnace`, so a legitimately-out-of-ore cycle fails fast and loud rather than waiting out the full engine timeout every time.
- **Add post-deposit verification**: after clicking deposit-all, poll the previously-tracked smelt indicator slot (or a full-inventory empty check) before proceeding into the withdraw loop, catching a failed/partial deposit before it corrupts the next cycle's withdraw math.
- Both `.ini`'s inert `withdrawSlot2*` keys (present but unused while `withdrawSlotCount=1` for gold) are safe as-is; if hand-editing gold's plan to add a second ore, double check both `withdrawSlot2Index` and `withdrawSlot2Clicks` are updated together, not copy-pasted from mithril's values.
