# Starter prompt — paste this as your first message in a new session

Continuing the OSRS automation project (AutoHotkey v2, repo root: this folder). Before doing anything, check your memory for `v6-rebuild-progress` and `v6-working-rules`, and read the plan file at `C:\Users\link\.claude\plans\role-you-are-whimsical-hanrahan.md` for full history/context. Don't re-litigate anything already decided in there (v5 is deleted, v6 is now the repo root directly — no more `v6\` prefix on any path, everything lives in `Lib\`, `Bots\`, `micro\`, `logs\`, `img\` at repo root).

**Current state:**
- `Bots\woodcutting.ahk` — confirmed working end-to-end in-game.
- `Bots\motherlode.ahk` — PART 1 only (mine veins → deposit into hopper → repeat 7 times → alarm + stop; no rockfall clearing, sack withdrawal, banking, or return-walk yet — those are later parts, done manually for now). Currently being live-tuned against real gameplay logs, not yet fully confirmed.

**How we work (don't skip these):**
- Never guess AutoHotkey v2 syntax — check `AutoHotkey.pdf` (repo root, read via `pdftotext`) first.
- Never trust "looks like it works" — read the actual log file (`logs\motherlode.log` / `logs\woodcutting.log`) before concluding anything, and check line counts/timestamps for context (multiple runs can be in one log file).
- When a bug is reported, diagnose from the log FIRST, form a concrete theory grounded in what the log actually shows, and say what you found before proposing a fix — don't guess-and-patch blind. If you've already guessed wrong once on the same issue, stop guessing and ask for real diagnostic data (e.g. `F8` probes, or run `micro\09-slot-check.ahk` for a full 28-slot grid) instead of trying a third blind fix.
- Tune one constant at a time, explain why, and leave a comment in the code with the reasoning (see existing comments in `Bots\motherlode.ahk` / `Lib\Steps.ahk` for the style — e.g. the `MAX_DRIFT_PX`/`TRACK_RADIUS_PX` tuning history).
- Don't add new Lib composites/abstractions speculatively — only promote something to `Lib\` once a second real caller needs the same shape (matches how `Lib\Config.ahk` and `AnySlotEmpty`'s "inventory full" use were both deliberately NOT built/reused speculatively).
- Keep the plan file and memory current, not an append-only log — prune resolved incident write-ups down to durable facts once confirmed fixed.

**Likely next steps:** keep live-tuning `Bots\motherlode.ahk`'s vein-tracking constants (`TRACK_RADIUS_PX`, `MAX_DRIFT_PX`, `ACQUIRE_RADII`) from real log evidence until a full 7-cycle run works cleanly with correct single hopper-clicks and no false "different block" rejections. After that's confirmed, later parts (rockfall clearing, sack withdrawal, banking, return-to-mine walk) are still queued.
