; ============================================================
;  TaskRunner.ahk
;  A small named-phase state machine that covers BOTH shapes the
;  old scripts used by hand:
;    - smelter-1's explicit phases (smelt -> wait_ore_end -> bank
;      -> return)
;    - miner-3/motherlode's reactive loop ("check condition, click
;      or wait, repeat") - which is really just a 1-2 phase
;      machine that never got named as one
;
;  Each phase is a function that takes the runner and returns the
;  name of the NEXT phase to run (return the same name to stay in
;  this phase and tick again next interval - this is exactly how
;  the old reactive loops behaved, just without a name for it).
;
;  Built-in safety nets the old scripts were missing:
;    - a busy-guard (generalizing smelter-1's manual cycleBusy
;      flag) so a slow phase can never overlap itself
;    - an optional per-phase timeout that force-stops the runner
;      if a phase gets stuck (this is the structural fix for the
;      "infinite wait with no timeout" bug found in every script)
;    - a try/finally around every phase call so an error mid-phase
;      can't permanently wedge the busy flag
;
;  Depends on: Tooltip.ahk (ShowTip/ShowTipFor)
; ============================================================

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
    ; SetTimer needs the SAME function reference to start and stop a
    ; timer - store one bound closure on the runner itself so
    ; StartTaskRunner/StopTaskRunner always pass that exact reference.
    runner["tickFn"] := () => TickTaskRunner(runner)
    return runner
}

; Registers a phase function under `name`. timeoutMs (default 0 =
; unlimited) auto-stops the runner with a tooltip if it stays in
; this phase longer than that - set a real value for any phase
; that waits on game state (ore respawn, smelting, banking) so it
; can never hang silently forever.
AddPhase(runner, name, phaseFn, timeoutMs := 0) {
    runner["phases"][name] := phaseFn
    runner["timeouts"][name] := timeoutMs
}

; Sugar for use inside a phase function: `return GoToPhase(runner, "bank")`
; reads more clearly than a bare string literal.
GoToPhase(runner, name) {
    return name
}

; A phase's timeoutMs is measured from the moment that phase name
; was entered - NOT reset just because the phase function returns
; its own name again. That's correct for a phase that's genuinely
; stuck waiting, but wrong for a phase like "mine" that's SUPPOSED
; to stay active for minutes while successfully gathering. Call
; this from inside a phase function whenever it makes real
; progress (e.g. right after a successful click) so the timeout
; means "no progress for this long", not "total time in phase".
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

; The timer callback. Not normally called directly - StartTaskRunner
; wires it up - but safe to call manually for single-step debugging.
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
