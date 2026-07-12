# osrs-automation

A from-scratch, config-driven automation framework for Old School RuneScape, written in native object-oriented [AutoHotkey v2](https://www.autohotkey.com/). It works entirely by reading pixels on screen and moving/clicking the mouse — no game memory reading, no network packet injection, no client modification.

The framework is built like Lego: small reusable pieces (a "Phase," a "Gate," a timing profile, a `.ini` config file) that snap together into a bot. Once you understand the pieces, building a new bot for a different training method is mostly copy-adjust-recalibrate, not writing new engine code.

## ⚠️ Before you use this

This automates gameplay in a live game (Old School RuneScape, by Jagex). Using automation software of this kind is against Jagex's Rules of Conduct and can get an account banned. This project is shared **for educational purposes** — to learn AutoHotkey v2, screen-based automation techniques, and state-machine bot architecture. You are responsible for how you use it and for any consequences to any account you use it on. Nobody involved in this project is responsible for banned accounts, lost items, or anything else that happens as a result of running this code.

## What's actually here

- **`v4/`** — the current, active framework. Everything described below lives here. Start here.
- **`lib/`, `scripts/`, `config/`, `docs/`, `images/`, `logs/`, `templates/`** (repo root) — an older iteration of this project, kept around only as historical reference. It's not maintained and some of its own docs (`docs/`) refer to a version that no longer exists. Don't build on it — build on `v4/`.

## Requirements

- Windows (this uses Windows-only screen/pixel APIs)
- [AutoHotkey v2.0](https://www.autohotkey.com/download/) installed
- OSRS running in a **fixed-size client window** — every coordinate in every `.ini` file is calibrated against one specific window size/position. If your client is a different size, every coordinate needs recalibrating (see `v4/GETTING_STARTED.md`).

## Quick start

1. Install AutoHotkey v2.
2. Clone this repo.
3. Pick a bot under `v4/Bots/` — e.g. `v4/Bots/Firemaking/firemaking.ahk` is the simplest one to read first.
4. Open its matching `.ini` in `v4/Config/` and recalibrate the coordinates/colors to your own screen (see `v4/GETTING_STARTED.md` for how — this step is unavoidable, nobody's screen setup matches another's exactly).
5. Double-click the bot's `.ahk` file to launch it (or run it via the AutoHotkey v2 interpreter).
6. Get your character into the right starting position/state in-game (each bot's own doc comment at the top of its file says what it assumes), then press **F5** to start, **F6** to stop.
7. Watch `v4/logs/<bot-name>-debug.log` while it runs — every phase transition, click, and timeout gets logged there, which is the fastest way to tell what a bot is actually doing (or why it stopped).

## How it's organized

Every bot is a small state machine: a handful of **Phases** (e.g. "walk to the fire," "wait for the burning animation to finish," "walk to the bank") that hand off to each other in a loop. Every Phase reads its behavior — coordinates, colors, timings, thresholds — entirely from that bot's own `.ini` file. Nothing is hardcoded in the bot's code, so tuning a bot for your own screen/account/preferences never means editing the `.ahk` file itself.

- **`v4/GETTING_STARTED.md`** — start here if you want to understand the building blocks and build your own bot. Written for someone who has never touched this codebase before.
- **`v4/ARCHITECTURE.md`** — the full reference: every shared class, every gate, every pattern, every known gotcha discovered while building the 5 existing bots. Denser, meant to be searched/skimmed once you already understand the basics from `GETTING_STARTED.md`.
- **`v4/CURRENT_STATE.md`** — a status snapshot of what's built and working right now.

## License

MIT — see [LICENSE](LICENSE). Do whatever you want with the code; there's no warranty and no support obligation.
