; ============================================================
; v7 micro 26 - shared bot run/stop harness (InstallBotHarness, Bot.ahk)
;
; The last micro before Step 3. Validates the NEW Bot.ahk composite that
; will replace every future bot's hand-rolled F5/F6/F12 wiring (see
; Lib\Bot.ahk's header for the full "why" - the 7-way duplication this
; fixes across v6's autoclicker/crafting/motherlode2/seller/smithing/
; sudoku/woodcutting).
;
; This micro's `run` is a deliberate DO-NOTHING loop (just ticks a
; counter and logs, never clicks or searches anything) - what's being
; tested here is ONLY the harness mechanics (start/stop/restart, F8
; probe, extra hotkeys, exit), not any real gather/bank/search logic
; (already covered by every earlier micro).
;
; STANDARD #5 EXCEPTION (deliberate): every other micro exits via Esc.
; This one exits via F12 instead, matching what Bot.ahk actually wires
; (F12 = exit) - since testing the real bot harness IS the point, this
; micro intentionally uses the same exit key real Step 3 bots will use,
; not the micro-only Esc convention. No Esc:: hotkey is defined here at
; all.
;
; TWO extra hotkeys (F9, F10) are wired with clearly DIFFERENT, easily
; distinguishable log messages - not because a real bot needs two, but
; specifically to catch the closure-per-entry bug described in Bot.ahk's
; header comment (a naive `for entry in extraHotkeys` loop would make
; every extra hotkey call the LAST handler registered) - if F9 ever logs
; F10's message or vice versa, that bug is back.
;
; WHAT IT DOES
;   F5  = start the do-nothing tick loop (installed by InstallBotHarness)
;   F6  = request stop (installed by InstallBotHarness)
;   F8  = probe: logs the current tick count without stopping anything
;   F9  = extra hotkey #1: logs a FOO-specific message
;   F10 = extra hotkey #2: logs a BAR-specific message
;   F12 = exit (installed by InstallBotHarness)
;
; LIVE CONFIRM:
;   1. Press F5 - confirm "micro26: started" logs, then repeating tick
;      messages every TICK_MS.
;   2. Press F8 mid-run - confirm it logs the current tick count and
;      does NOT interrupt the tick loop.
;   3. Press F9 - confirm ONLY the FOO message logs (not BAR). Press F10 -
;      confirm ONLY the BAR message logs (not FOO). Neither should ever
;      cross-fire the other's message.
;   4. Press F5 AGAIN while already running (double-F5 sanity) - confirm
;      this does NOT spawn a second overlapping tick loop (AHK's default
;      one-thread-per-hotkey behavior should just ignore the extra press
;      - watch the log for any doubled-up tick lines).
;   5. Press F6 - confirm "micro26: STOPPED by F6" logs and ticking stops.
;   6. Press F5 again after stopping (restart sanity) - confirm it starts
;      clean from tick 1 again, not from wherever it left off.
;   7. Press F12 - confirm the script exits.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "26-bot-harness"

; ======= EDIT THESE FOR YOUR TEST =======================================
TICK_MS := 1000
; ========================================================================

tickCount := 0

DoNothingLoop() {
    global tickCount
    tickCount := 0
    loop {
        tickCount += 1
        Say("micro26: tick " tickCount)
        Pause(TICK_MS)
    }
}

ProbeStatus() {
    global tickCount
    Say("micro26: PROBE - tickCount=" tickCount)
}

FooHandler() {
    Say("micro26: F9 pressed - FOO handler fired")
}

BarHandler() {
    Say("micro26: F10 pressed - BAR handler fired")
}

InstallBotHarness({
    run: DoNothingLoop,
    label: "micro26",
    probe: ProbeStatus,
    extraHotkeys: [
        {key: "F9", handler: FooHandler, label: "foo"},
        {key: "F10", handler: BarHandler, label: "bar"}
    ]
})
