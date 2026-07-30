# How to ask for a new script/bot (so it gets built right, fast)

This is for the human working on this project — a checklist for phrasing
requests so an agent can build/tune scripts correctly on the first or second
pass instead of several corrections in. Based on real friction points from
past sessions (each numbered `PROGRESS.md` standard exists because a request
was ambiguous or under-specified in exactly one of these ways).

## 1. Describe the flow as numbered steps, in order

Say what happens, in sequence, as if narrating the bot's loop. This is the
single highest-leverage thing you can do — every bot built so far started
from a numbered flow like this:

> 1. Search for X around the character, do Y until condition Z.
> 2. Search region W for marker M, wait for image I to appear, click it.
> 3. Loop back to step 1.

Vague requests ("make it bank when full") force a guess about the actual
mechanism (which marker? which region? which image confirms success?).

## 2. Say whether a position/color is already measured, or needs measuring

If you already know a color hex, a pixel position, or an image file, give it
exactly (`#CC5D02`, `x=775 y=765`, `deposit-box.png`). If you don't have it
yet, say so explicitly — don't let a placeholder guess get treated as real
calibration.

## 3. Say whether something is a fixed screen position or per-location config

This distinction has caused the most back-and-forth historically (see
`PROGRESS.md` standard #17). If a button/marker sits at the exact same pixel
spot no matter what the bot is doing (e.g. a UI button), say "this is
fixed/constant." If it can vary by location/target (e.g. a bank marker that
differs per bank), say that too. When you're not sure, say "not sure if this
is fixed or varies — check before assuming."

## 4. Name the region, don't default to "search everywhere"

Say which part of the screen a thing lives in, even roughly ("top-right
quadrant of the game area," "somewhere in the inventory," "a small area
around the character"). A whole-screen/whole-region search is a fallback of
last resort, not a default — vague scope produces slower and less precise
searches than necessary.

## 5. Say what "done"/"stop" looks like for a loop

For anything that runs until a condition (inventory full, marker gone, N
cycles), name the condition explicitly, and say whether it's a real
indefinite bot (loop forever until F6) or a bounded test run (stop after N
cycles).

## 6. Flag timing observations with real numbers, not just "feels slow"

If something feels off timing-wise, say what you actually observed
("felt like >100ms between the click and the tree search") — that turns
into a log-verified answer instead of a guess. If you want a delay/settle
added, say where in the sequence (before/after which action).

## 7. When correcting something, say why, even briefly

"This shouldn't be a global" lands faster with "because it varies per bank"
than alone — the reason is what turns into a durable standard instead of a
one-off fix that regresses later. (Every numbered standard in `PROGRESS.md`
carries the "why," not just the rule — that's deliberate; it's what let
later sessions apply the rule to new, similar-but-not-identical cases
correctly instead of misapplying it.)

## 8. Reference an existing bot/composite when you want the same shape

"Same as woodcutting but for X" or "reuse `DepositAllToBank`" resolves
ambiguity instantly if a close analog already exists — check `Bots\` and
`PROGRESS.md`'s file map first.

## 9. It's fine to not know the mechanism — just say what you want to see happen

You don't need to know which Lib function should be used. Describing the
in-game behavior you want ("wait for the deposit box image, then click it")
is enough — mapping that to `Lib\` calls is the agent's job. Just be
concrete about the *in-game* behavior, not the code.

## 10. Batch related corrections together when live-testing

If you're about to test a bot and already know of 2-3 things you want
changed, list them all at once (numbered) rather than one at a time across
separate messages — it's faster to apply and easier to keep the reasoning
attached to each specific change (see rule 7).
