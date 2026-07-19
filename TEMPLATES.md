# Bot Logic Templates (v6 Stage 0)

Plain-English step breakdowns of all 10 bots, distilled from the v5 scripts.
These are the **specs** for the v6 ports. Format: `condition -> action [target type]`.
Concrete colors, regions, and coordinates live in each bot's INI under `Config\`
— templates reference them by name.

Building-block vocabulary used below (v6 names):
- **FindColor [name]** — find a solid color block (region-limited when possible, steered toward a known point)
- **FindImage [name.png]** — find a PNG on screen or in a region
- **FindBlob [name]** — find nearest irregular color blob (NPC overlays); always region-limited
- **Click / CtrlClick [target or point]** — settled click (100ms settle before the click; CtrlClick holds Ctrl an additional 100ms after the click before releasing — load-bearing, not redundant, confirmed live: releasing sooner risks the client not registering the held modifier, so the character walks instead of runs)
- **TrackAndClick** — acquire a target, keep tracking it in a small box, re-click when it depletes/moves, until a condition
- **PickupAppeared** — wait for a thing to appear -> snapshot a confirm box -> click it -> confirm the box changed (the Mark-of-Grace block)
- **WaitFor / WaitUntil** — interruptible wait with timeout (300ms tick-aligned polls)
- **Slot N full/empty, InvFull, InvEmpty** — inventory pixel checks

---

## Woodcutting
```
Loop:
  TrackAndClick [tree color] until InvFull
  FindColor [bank marker] -> Click
  WaitFor [deposit-box.png] -> Click it
  Click [post-deposit point] -> pause -> repeat
```

## Firemaking
```
Loop:
  FindColor [fire marker, green] -> verify -> Click
  WaitFor [craft-marker-1.png]  (burn dialog open)
  Press Space -> WaitUntil InvEmpty  (logs burned)
  FindColor [bank marker, blue] -> Click
  WaitFor [bank open image]
  Withdraw plan: for each (slot, clicks): Click [bank slot N] x clicks
  repeat
```

## Smelter
```
Loop:
  FindColor [furnace marker, magenta] -> verify -> Click
  WaitFor [craft-marker-1.png]  (smelt dialog)
  Press Space
  Snapshot [ore slot] -> WaitUntil slot signature CHANGES  (ore became bar — slot never empties!)
  FindColor [bank marker] -> Click -> WaitFor [bank open image]
  Click [deposit-all] -> run withdraw plan -> repeat
```

## Smithing
```
Same skeleton as Smelter, except:
  FindColor [anvil marker] instead of furnace
  Press Space -> WaitUntil InvEmpty  (bars fully leave slots, unlike smelting)
  Deposit + withdraw plan -> repeat
```

## Motherlode (walking variant)
```
Phase mine:      if InvFull -> go clearRed
                 else TrackAndClick [vein overlay, 2 candidate colors, pick nearer to reference point]
Phase clearRed:  TrackAndClick [red rockfall color, whole scan region] until none found -> clearYellow
Phase clearYellow: if InvEmpty -> withdrawSack
                 else FindColor [hopper] -> Click  (deposit pay-dirt)
Phase withdrawSack: Click [sack point] -> WaitUntil slot 2 OR slot 12 full -> depositBank
Phase depositBank: FindColor [magenta deposit marker] -> Click
                 WaitFor [deposit-all image] -> Click it
Phase return:    Click waypoint 1 [fixed point] -> WaitFor [waypoint marker color]
                 Click waypoint 2 -> WaitFor [mine area marker] -> reset cycle state -> mine
```

## MotherlodeFixed (stand-still variant)
```
Exactly 2 known vein positions; character never walks.
Phase mine:    check vein A / vein B at fixed points [color check with clamped boxes]
               active vein missing N consecutive ticks -> vein depleted -> re-check both
               if InvFull -> depositBank
Phase depositBank: FindColor [magenta marker, small fixed region] -> Click
               WaitFor [deposit-all image] -> Click it
Phase return:  Click [return point] -> WaitUntil a vein is visible again -> mine
```

## AutoFighter
```
Loop:
  FindBlob [NPC overlay color, bounded box around reference point] -> Click centroid
  WaitUntil [combat indicator pixel]:
    green = fighting -> keep waiting (progress!)
    dark red = kill confirmed -> settle -> repeat
    (guard: ignore kill color that was already present at entry — corpse lingers ~3s)
  no signal within timeout -> re-scan
```

## AutoFighterLoot
```
Same as AutoFighter, but after each kill:
  FindImage [bb-item.png] -> RIGHT-Click it
  FindImage [take-bb.png] (context menu) -> Click it
  Click [inventory slot 1]  (use/bury the loot)
  loot not found -> just log and return to scanning (never stop the engine for loot)
```

## FruitStall
```
Loop:
  if [stall ready pixel] matches -> Click [stall point]
  WaitUntil slot 1 full (loot landed) -> Click [slot 1]  (drop/eat)
  loot never lands within timeout -> assume guard caught us -> WaitCombat (same block as AutoFighter)
  after combat ends -> back to stall
```

## Agility
```
For each course step 1..N (from [Step:N] config sections):
  FindColor [step N highlight color] in [step N calibrated box]
    (or in EXPANDED search area if a detour just happened — dynamic region)
  not found + just after the fall-prone step -> FindColor [fall recovery block] -> Click -> restart at step 1
  found -> once per step: PickupAppeared [mog-item.png, confirm box = mark counter]
           (mark clicked -> confirm counter changed -> search area goes dynamic)
  Click [step N obstacle] -> advance to step N+1 (wrap to 1) -> repeat
```
