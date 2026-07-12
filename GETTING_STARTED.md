# Getting started

This document is for someone who has never seen this codebase before and wants to either **run an existing bot** or **build a new one**. It assumes you know roughly what AutoHotkey is, but not much else.

If you want the full technical reference (every class, every gate, every gotcha discovered building the existing bots), that's `ARCHITECTURE.md` — read this document first, then use that one as a lookup reference.

## The big idea

Every bot in this framework works the same way, whether it's chopping fire, smelting ore, or fighting cows:

1. **Look at the screen** for a specific color or image (a colored overlay OSRS paints on an object, or a screenshot of part of the UI).
2. **Click** what it found.
3. **Wait** for something to change (a dialog to appear, an inventory slot to empty, a pixel to change color).
4. **Repeat**, looping between a small number of named steps forever, until something goes wrong or you stop it.

Each named step is called a **Phase**. A bot is just a handful of Phases wired together in a loop, plus one `.ini` file that holds every number the Phases need (coordinates, colors, delays). Nothing about *where things are on your screen* or *how long to wait* is written in the code — it's all in the `.ini`. This is the single most important thing to understand: **if a bot doesn't work for you, the fix is almost always editing numbers in a `.ini` file, not editing code.**

## The building blocks (the "Lego bricks")

You don't need to understand every file in this repo to build a bot — you need to understand these five ideas:

### 1. A Phase

A Phase is one step in the loop. It gets handed a `ctx` (context) object with everything it needs, does one thing, and returns the name of whichever Phase should run next (including possibly its own name, meaning "nothing to do yet, try again next tick").

```ahk
class BurnLogsPhase extends Phase {
    Run(ctx) {
        ; ... look at something, maybe click, maybe wait ...
        return "goToBank"   ; hand off to the next phase
    }
}
```

The engine calls `Run(ctx)` on whichever phase is "current" every tick (by default every 50ms), and switches to whatever phase name got returned.

### 2. Detection — finding things on screen

Two ways a Phase finds something to click:

- **A color marker**: OSRS (or a plugin) paints a solid block of a specific color over something clickable (a tree, an anvil, an NPC). `ColorSearch.FindFilledBlock(...)` searches a small region for that color and returns its center point.
- **An image anchor**: a small screenshot (`.png`, stored in `Images/`) of something that appears in a fixed place, like a dialog box or the bank interface. `StaticAnchor.ImageAnchor(...)` searches for that image and waits until it appears.

Both answer the same question: "is the thing I'm looking for here yet, and if so, where exactly?"

### 3. Gates — "is a condition true?"

A **Gate** answers a yes/no question about game state, usually "is this inventory slot occupied?" The most common one, `SlotGate`, checks whether a specific inventory slot's color still matches the known "empty slot" background color. Gates can be combined (`AndGate`, `OrGate`, `NotGate`) and are how a Phase knows "the inventory is full, stop chopping" or "the inventory is empty, go get more logs."

### 4. Waiter — every pause goes through one place

Every single delay in every bot — "wait 100ms after moving the mouse before clicking," "wait 600ms after withdrawing before searching again" — is a named key in that bot's `.ini` file, read through one method: `ctx.waiter.After(ctx.timing, "someDelayName")`. There is no other way to pause in this framework. This matters because it means **every timing issue you'll ever need to fix is a number in an `.ini` file**, not a line of code buried in a Phase.

### 5. The `.ini` file — the only place numbers live

Open `Config/auto-firemaking-v2.ini` and skim it. Every coordinate, every color, every millisecond delay used by the Firemaking bot is in there, organized by which Phase uses it, with a comment explaining what it's for. If a bot misses a click, searches too slowly, or waits too long, the fix is almost always tuning a value in this file — not touching `firemaking.ahk` itself.

## Worked example: reading the Firemaking bot

`Bots/Firemaking/firemaking.ahk` is the simplest existing bot — a good first read. Its loop is 4 phases:

```
goToFire  ->  burnLogs  ->  goToBank  ->  withdrawLogs  ->  (back to goToFire)
```

- **`goToFire`**: searches for a green color marker at a calibrated point (`fireMarkerX/Y` in the `.ini`). Once found, clicks it, then waits for `craft-marker-1.png` (a screenshot of the "burn logs" dialog) to appear.
- **`burnLogs`**: presses Space to confirm the dialog, then just waits until the inventory is empty (checked via a `SlotGate` on the last inventory slot — logs fill inventory front-to-back, so the *last* slot becoming empty means "all logs burned"). This phase is actually a reusable generic class, `PressAndWaitEmptyPhase` — Firemaking didn't need to write its own version, it's shared with the Smithing bot too, since "press a key, wait for empty inventory" is a common shape.
- **`goToBank`**: searches for a blue bank-booth marker, clicks it, waits for the bank interface to visibly open (another image anchor). Also a reusable shared class, `GoToBankPhase`.
- **`withdrawLogs`**: clicks a specific bank slot the configured number of times (from the `.ini`'s `withdrawSlot1Index`/`withdrawSlot1Clicks`), waits a settle delay, resets all the "have I clicked X yet" scratch flags back to their starting state, and hands back to `goToFire` — starting the loop over.

Every coordinate/color/delay mentioned above lives in `Config/auto-firemaking-v2.ini`, grouped under a comment block per phase.

## Building your own bot

The fastest way to build a new bot is to **copy the shape of an existing one that's closest to what you want**, then change three things: the markers/colors/coordinates, the images (if any), and the specific wait condition for "am I done with this step."

1. **Pick the closest existing bot as a template.** Simple "walk somewhere, do a repeatable action, walk to bank, withdraw, repeat" bots should start from Firemaking or Smithing. A bot that needs to scan a wider area for multiple possible targets (like fighting NPCs) should look at AutoFighter instead.
2. **Copy its folder** under `Bots/<YourBotName>/`, and copy its `.ini` under `Config/`.
3. **Recalibrate every coordinate and color** to your own screen. This is unavoidable — nobody's OSRS client window is in the exact same position/size as anyone else's. Use AutoHotkey's `Window Spy` tool (ships with AutoHotkey) or a simple pixel-color-reading script to find your own coordinates.
4. **Check whether your "done" condition actually empties an inventory slot, or just changes it.** This trips people up: if your action *consumes* an item and leaves nothing behind (like burning logs), the shared `PressAndWaitEmptyPhase` works fine. But if your action *transforms* an item into something else that still occupies the slot (like smelting ore into a bar — the slot never becomes empty, it just looks different), you need `SlotSignatureGate` instead, which detects "this slot's contents changed" rather than "this slot became empty." Using the wrong one is a bug that's easy to make and easy to miss — the bot will just seem to hang forever waiting for a slot to empty that was never going to empty. See `ARCHITECTURE.md`'s Telemetry section for how this gate works, or read `Bots/Smelter/smelter.ahk`'s `SmeltPhase` for a working example.
5. **Load-check before testing in-game.** Run your `.ahk` file through the AutoHotkey v2 interpreter and confirm it starts without errors before pressing F5 in-game — a typo or missing `.ini` key will show up immediately this way instead of mid-run.
6. **Watch the debug log while testing**, not just the screen. `logs/<your-bot>-v4-debug.log` records every phase transition and click with a timestamp — if a bot seems stuck, the log almost always shows exactly which phase it's stuck in and why (usually: "waiting for X, timed out" or "clicked the same marker repeatedly with nothing changing," which usually means a wrong color/coordinate, not a code bug).

## A few things that trip people up

- **Coordinates are per-screen.** Every `.ini` value in this repo was calibrated against one specific person's screen resolution and OSRS window layout. Copying someone else's `.ini` file as-is will not work on a different setup — you must recalibrate.
- **A repeated click with no progress almost always means a detection problem, not a click problem.** If the debug log shows the same "clicked marker at [x,y]" line repeating every few seconds with nothing else happening, the color/image search is failing (wrong color value, wrong tolerance, wrong coordinates) even though the click itself might be landing somewhere that happens to do something in-game. Don't assume "it clicked so detection must be fine."
- **Full-screen pixel scans can be surprisingly slow.** If a bot needs to search a large area of the screen (not a single fixed point), be aware that scanning many rows/pixels can take much longer than expected on some machines — see `ARCHITECTURE.md`'s AutoFighter section for a concrete example of this and how it was worked around (shrinking the search area beats coarsening the scan).
- **Humanization/randomization plumbing exists but is switched off everywhere** (`Humanizer(enabled=false, ...)` in every bot). It's inert scaffolding, not a bug — nothing currently adds click-position or timing randomness. It's left in place rather than removed, in case a future version wants it.

## Where to go next

- `ARCHITECTURE.md` — the full reference once you're past the basics.
- `CURRENT_STATE.md` — a snapshot of what's built and verified right now.
- Read an existing bot's `.ahk` file end to end alongside its `.ini` — that's a better way to internalize the pattern than reading the shared framework classes in isolation.
