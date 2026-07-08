; ============================================================
; TaskRunner.ahk - v3 PORTED
;
; Named-phase state machine. Covers both script shapes:
; - Explicit phases (smelt → wait → bank → return)
; - Reactive loops ("check condition, click or wait, repeat")
;
; Each phase is a function(runner) that returns the NEXT phase name.
; Return the same name to stay in that phase and tick again.
;
; Built-in safety nets:
; - busy-guard: slow phase can't overlap itself
; - per-phase timeout: force-stops if a phase gets stuck
; - try/finally: phase errors can't wedge the busy flag
;
; Depends on: Tooltip.ahk (ShowTipFor)
; ============================================================

#Requires AutoHotkey v2.0

#Include Tooltip.ahk

NewTaskRunner(intervalMs := 150) {
    runner := Map(
        "running", false,
        "busy", false,
        "phase", "",
        "phases", Map(),
        "timeouts", Map(),
        "intervalMs", intervalMs,
        "phaseEnteredAt", 0
    )
    ; SetTimer needs the SAME function reference to start and stop -
    ; store one bound closure on the runner so StartTaskRunner/StopTaskRunner
    ; always pass that exact reference.
    runner["tickFn"] := () => TickTaskRunner(runner)
    return runner
}

; Registers a phase function under `name`. timeoutMs (default 0 = unlimited)
; auto-stops the runner if it stays in that phase longer than the specified
; time - set a real value for any phase that waits on game state so it can't
; hang silently forever.
AddPhase(runner, name, phaseFn, timeoutMs := 0) {
    runner["phases"][name] := phaseFn
    runner["timeouts"][name] := timeoutMs
}

; Sugar: return GoToPhase(runner, "bank") is clearer than a bare string.
GoToPhase(runner, name) {
    return name
}

; Resets the phase timer. A phase's timeoutMs is measured from when that
; phase name was entered, NOT reset just because the phase function returns
; its own name again. Call this from inside a phase after making real
; progress (e.g. right after a successful click) so the timeout means
; "no progress for this long", not "total time spent in phase".
ResetPhaseTimer(runner) {
    runner["phaseEnteredAt"] := A_TickCount
}

StartTaskRunner(runner, startPhase) {
    runner["running"] := true
    runner["busy"] := false
    runner["phase"] := startPhase
    runner["phaseEnteredAt"] := A_TickCount
    SetTimer(runner["tickFn"], runner["intervalMs"])
}

StopTaskRunner(runner, reason := "Stopped") {
    runner["running"] := false
    SetTimer(runner["tickFn"], 0)
    ShowTipFor(reason, 1500)
}

; The timer callback. Safe to call manually for single-step debugging.
TickTaskRunner(runner) {
    if (!runner["running"] || runner["busy"])
        return

    timeoutMs := runner["timeouts"].Has(runner["phase"]) ? runner["timeouts"][runner["phase"]] : 0
    if (timeoutMs > 0 && (A_TickCount - runner["phaseEnteredAt"]) > timeoutMs) {
        StopTaskRunner(runner, "Phase '" runner["phase"] "' timed out - stopped")
        return
    }

    if (!runner["phases"].Has(runner["phase"])) {
        StopTaskRunner(runner, "Unknown phase '" runner["phase"] "' - stopped")
        return
    }

    runner["busy"] := true
    try {
        nextPhase := runner["phases"][runner["phase"]](runner)
    } finally {
        runner["busy"] := false
    }

    if (nextPhase != runner["phase"]) {
        runner["phase"] := nextPhase
        runner["phaseEnteredAt"] := A_TickCount
    }
}
