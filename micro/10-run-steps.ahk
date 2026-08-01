; ============================================================
; v8 micro 10 - the fail-safe engine (Run.ahk: RunSteps, StepLoop)
; + Session.ahk pacing
;
; No real game state needed - same precedent as v7 micro 28's dummy
; closures. This micro deliberately lands BEFORE any real composite
; (TrackAndClick, DepositAllToBank) is wired through StepLoop, so
; the engine is proven pure first - same isolation lesson as the
; IdleWander postmortem (a feature that failed live and had to be
; ripped out; this feature is scoped so it can be fully verified with
; nothing but dummy closures before it ever touches real clicks).
;
; Test values are deliberately fast/aggressive (seconds, chance=1.0),
; not the real Lib defaults - a tester should not wait an hour to
; see a session end.
;
; WHAT IT DOES
;   F5  = StepLoop, 2-step dummy cycle (gather/bank, both always
;         succeed), breaks+session-length ENABLED at aggressive test
;         values - runs until session expiry (or F6)
;   F6  = request stop (must interrupt instantly even mid-break)
;   F7  = StepLoop REGRESSION run: same 2 steps, breakChance/
;         sessionLengthMs OMITTED, maxCycles=3 - proves zero
;         break/session logging and old-GatherBankLoop-shaped
;         behavior when a caller doesn't opt in
;   F8  = probe: RunSteps with a step that FAILS once then succeeds
;         - watch exactly one retry happen, then overall success
;   F9  = RunSteps with a step that ALWAYS fails - watch both
;         attempts fail, then "FAILED after 2 attempt(s)", RunSteps
;         returns false, WrapHandler reports FAILED (script/hotkeys
;         stay alive - press F9 again or F5 to keep testing)
;   F10 = RunSteps with a step whose run() always returns true but
;         whose `done` indicator never becomes true (short
;         doneTimeoutMs) - proves a "looks done but isn't confirmed"
;         step is treated as a failure and retried the same as a
;         hard run() failure
;   F11 = RunSteps with retries:0 on the step (per-step override) -
;         fails once, NO retry attempt logged, immediate FAILED -
;         regression check for the retries:0 case
;   F12 = exit
;
; LIVE CONFIRM:
;   1. F5 - cycle 1 runs both dummy steps, then (chance=1.0) ALWAYS
;      logs a break, pauses, resumes, cycle 2 starts. Let it run past
;      the test session length - confirm "session length elapsed
;      after cycle N - stopping cleanly" and a true/DONE result.
;   2. F6 mid-break during an F5 run - stops within ~40ms, not after
;      the break finishes.
;   3. F7 - confirm ZERO break/session log lines, stops via
;      maxCycles=3 exactly like a caller that never opted in.
;   4. F8 - exactly one "failed (attempt 1/2) - retrying fresh" line,
;      then success, RunSteps returns true.
;   5. F9 - "failed (attempt 1/2)" then "FAILED after 2 attempt(s)",
;      handler reports FAILED, script still responds to F5/F9 again.
;   6. F10 - same FAILED shape as F9, but caused by the done-timeout
;      path, not run() returning false.
;   7. F11 - FAILED after exactly ONE attempt, no retry line at all.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v8.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "10-run-steps"

; ======= EDIT THESE FOR YOUR TEST =======================================
CYCLE_WORK_MS := 500

TEST_BREAK_CHANCE := 1.0
TEST_BREAK_MS := [2000, 4000]
TEST_SESSION_LENGTH_MS := [8000, 12000]

DONE_TIMEOUT_MS := 1000
; ==========================================================================

DummyGather() {
    Say("micro10: gathering (dummy, " CYCLE_WORK_MS "ms)")
    Pause(CYCLE_WORK_MS)
    return true
}

DummyBank() {
    Say("micro10: banking (dummy, " CYCLE_WORK_MS "ms)")
    Pause(CYCLE_WORK_MS)
    return true
}

RunWithPacing() {
    return StepLoop({
        steps: [{name: "gather", run: DummyGather}, {name: "bank", run: DummyBank}],
        maxCycles: 0, label: "micro10",
        breakChance: TEST_BREAK_CHANCE, breakMs: TEST_BREAK_MS,
        sessionLengthMs: TEST_SESSION_LENGTH_MS
    })
}

RunRegression() {
    return StepLoop({
        steps: [{name: "gather", run: DummyGather}, {name: "bank", run: DummyBank}],
        maxCycles: 3, label: "micro10-nopacing"
    })
}

; fails on the first call, succeeds on every call after
FailOnceThenSucceed() {
    static calls := 0
    calls += 1
    ok := (calls > 1)
    Say("micro10: FailOnceThenSucceed call " calls " -> " ok)
    return ok
}

ProbeFailOnce() {
    return RunSteps([{name: "flaky", run: FailOnceThenSucceed}], {label: "micro10-probe"})
}

AlwaysFail() {
    Say("micro10: AlwaysFail called")
    return false
}

RunAlwaysFail() {
    return RunSteps([{name: "doomed", run: AlwaysFail}], {label: "micro10-alwaysfail"})
}

RunNeverDone() {
    return RunSteps([{
        name: "unconfirmed", run: () => true,
        done: () => false, doneTimeoutMs: DONE_TIMEOUT_MS
    }], {label: "micro10-neverdone"})
}

RunNoRetryOverride() {
    return RunSteps([{name: "no-retry", run: AlwaysFail, retries: 0}], {label: "micro10-noretry"})
}

InstallBotHarness({
    run: RunWithPacing,
    label: "micro10",
    probe: ProbeFailOnce,
    extraHotkeys: [
        {key: "F7", handler: RunRegression, label: "regression"},
        {key: "F9", handler: RunAlwaysFail, label: "always-fail"},
        {key: "F10", handler: RunNeverDone, label: "never-done"},
        {key: "F11", handler: RunNoRetryOverride, label: "no-retry-override"}
    ]
})
