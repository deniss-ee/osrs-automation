; ============================================================
; v7 micro 28 - session pacing (MaybeTakeBreak, NewSessionTimer,
; GatherBankLoop's breakChance/breakMs/sessionLengthMs), standard #30
;
; No real game state needed - same precedent as micro 26's do-nothing
; harness test. GatherBankLoop's gather()/bank() closures here are
; dummies (log + short Pause + return true); the ONLY thing under test
; is the NEW timing/loop-control surface: does a break actually fire
; and pause (F6-interruptible mid-break), does the session length
; check stop the loop CLEANLY (true, not false) after the seam, and -
; critically - does breakChance=0/sessionLengthMs omitted reproduce
; OLD GatherBankLoop behavior exactly (regression check, since
; Bots\woodcutting.ahk does not opt in by default and must be
; unaffected).
;
; Test values are deliberately fast/aggressive (seconds, chance=1.0),
; NOT the real Lib defaults (SESSION_BREAK_MS_DEFAULT/
; SESSION_LENGTH_MS_DEFAULT are 30s-3min / 1-2h) - a tester should not
; have to wait an hour to see a session end.
;
; F7's regression run resets g_StopRequested and wraps its own
; try/catch BotStopped (matching InstallBotHarness's RunWrapped) -
; unlike micro 26's trivial F9/F10 log-only extra hotkeys, this one
; runs a real GatherBankLoop that can throw on F6, and
; BindHotkeyHandler does NOT do either of those for extraHotkeys (only
; opts.run gets that wrapping) - so F7 needs its own, or a stale stop
; flag from an earlier F6 would abort it instantly.
;
; WHAT IT DOES
;   F5  = run GatherBankLoop with breaks+session-length enabled
;         (dummy gather/bank, TEST_MAX_CYCLES=0 so only the session
;         timer or F6 ends the run)
;   F6  = request stop (must interrupt instantly even mid-break)
;   F7  = run GatherBankLoop again with breaks/session-length
;         DISABLED (opts omitted) - regression check against old
;         behavior
;   F8  = call MaybeTakeBreak directly, in isolation, chance=1.0
;   F12 = exit
;
; LIVE CONFIRM:
;   1. F5 - confirm cycle 1 gathers/banks (dummy logs), then (chance=1.0)
;      ALWAYS logs "stepping away for a short break (Ns)" with N inside
;      TEST_BREAK_MS, pauses that long, logs "break over, resuming",
;      then cycle 2 starts automatically.
;   2. Let it run past TEST_SESSION_LENGTH_MS - confirm it logs
;      "session length elapsed after cycle N - stopping cleanly" and
;      the run ends with a DONE/true result, not a FAILED/false one.
;   3. Press F6 WHILE a break is in progress (mid-Pause) - confirm it
;      stops within ~40ms (BotStopped), not after the break finishes -
;      proves breaks are truly interruptible, not a blocking Sleep.
;   4. Press F8 standalone (loop not running) - confirm MaybeTakeBreak
;      logs and pauses correctly on its own, outside GatherBankLoop.
;   5. Press F7 (breakChance/sessionLengthMs both omitted) - confirm
;      ZERO break/session logging appears and the loop runs exactly
;      like the pre-standard-#30 GatherBankLoop (maxCycles or F6 only) -
;      this is the regression guarantee that Bots\woodcutting.ahk stays
;      unaffected until it explicitly opts in. Also confirm F6 during
;      an F7 run stops cleanly (no error dialog).
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "28-session-breaks"

; ======= EDIT THESE FOR YOUR TEST =======================================
CYCLE_WORK_MS := 1000              ; how "long" each dummy gather/bank pretends to take

TEST_BREAK_CHANCE := 1.0           ; 1.0 = always fires (removes RNG waiting)
TEST_BREAK_MS := [2000, 4000]      ; 2-4s, fast for testing
TEST_SESSION_LENGTH_MS := [8000, 12000]  ; 8-12s, so expiry is observable quickly
TEST_MAX_CYCLES := 0               ; 0 - let session length (not maxCycles) end the run
; ==========================================================================

DummyGather() {
    Say("micro28: gathering (dummy, " CYCLE_WORK_MS "ms)")
    Pause(CYCLE_WORK_MS)
    return true
}

DummyBank() {
    Say("micro28: banking (dummy, " CYCLE_WORK_MS "ms)")
    Pause(CYCLE_WORK_MS)
    return true
}

RunWithPacing() {
    result := GatherBankLoop({
        gather: DummyGather, bank: DummyBank, maxCycles: TEST_MAX_CYCLES, label: "micro28",
        breakChance: TEST_BREAK_CHANCE, breakMs: TEST_BREAK_MS,
        sessionLengthMs: TEST_SESSION_LENGTH_MS
    })
    Say("micro28: pacing run result=" result)
}

RunWithoutPacing() {
    global g_StopRequested
    g_StopRequested := false
    try {
        result := GatherBankLoop({
            gather: DummyGather, bank: DummyBank, maxCycles: 3, label: "micro28-nopacing"
        })
        Say("micro28: no-pacing (regression) run result=" result)
    } catch BotStopped {
        Say("micro28-nopacing: STOPPED by F6")
    }
}

ProbeBreakOnly() {
    MaybeTakeBreak({chance: 1.0, breakMs: TEST_BREAK_MS, label: "micro28-probe"})
}

InstallBotHarness({
    run: RunWithPacing,
    label: "micro28",
    probe: ProbeBreakOnly,
    extraHotkeys: [
        {key: "F7", handler: RunWithoutPacing, label: "no-pacing regression run"}
    ]
})
