; ============================================================
;  stamina.ahk - PER-COORDINATE RUN VS WALK DECISION
; ------------------------------------------------------------
;  ELI5: You run in-game by holding Ctrl while you click a tile
;  (a "force-run" click), instead of toggling a run setting. So
;  there's no need for the bot to read a stamina gauge at all -
;  it just needs to know, for EACH recorded click, whether you
;  marked it as "hold Ctrl here" (run) or not (walk). That flag
;  is recorded per-step in paths.ahk (toggle with F9 while
;  recording) and used here.
;
;  This file used to also read OSRS's run-energy orb color to
;  estimate stamina %% and gate running on that - removed because
;  it's not how this bot manages running (Ctrl-click handles it),
;  so it was unnecessary complexity.
; ============================================================

#Requires AutoHotkey v2.0

; --------------------------------------------------------------
; ShouldRun: should THIS specific recorded step be replayed as a
; Ctrl-click (run) instead of a plain click (walk)? Purely based
; on the flag you set for that step while recording (F9) - one
; coordinate at a time, exactly as requested.
; --------------------------------------------------------------
ShouldRun(step) {
    return step["run"]
}
