; ============================================================
; v8 Lib\Run.ahk - the fail-safe engine (NEW - v7 had no retry
; anywhere; every composite returned false on first failure and
; GatherBankLoop killed the whole session on one missed click)
;
; A STEP is: {
;   name:          required, string - used in every log/FAILED line
;   run:           required, closure -> bool - a FULL FRESH attempt
;                  every time it's called (fresh search + click, not
;                  a resume of a half-done attempt)
;   done:          optional, closure -> bool - the step's completion
;                  indicator, polled AFTER run() returns true
;   doneTimeoutMs: required iff `done` is present
;   retries:       optional, overrides opts.retries for this step
;   pollMs:        optional, overrides opts.pollMs for this step
; }
;
; Design decision: "completion indicator" is two-layered on purpose.
; Most existing composites (TrackAndClick's `until`, DepositAllToBank's
; `confirmCondition`, TravelToPoint's arrival check) already embed
; their own confirmation - for those, run()'s bool result IS the
; indicator and `done` is omitted. `done` is the OPTIONAL extra layer
; for a step whose composite can return true before the world has
; actually settled. "Wait for the next step's readiness" is expressed
; by simply using the NEXT step's precondition as THIS step's `done` -
; there is no separate `ready` field, so there's no ordering ambiguity
; and the engine stays a single straight-line loop.
;
; RunSteps runs a sequence ONCE, retrying each step in place (a full
; fresh attempt, not a resume) up to `retries` extra times before
; giving up on the WHOLE sequence. StepLoop wraps RunSteps in a
; cycle loop with maxCycles/session-pacing at the cycle seam -
; StepLoop is what REPLACES v7's GatherBankLoop.
; ============================================================

RunSteps(steps, opts := {}) {
    defRetries := Opt(opts, "retries", 1)
    defPollMs := Opt(opts, "pollMs", POLL_MS_DEFAULT)
    label := Opt(opts, "label", "RunSteps")

    for step in steps {
        retries := Opt(step, "retries", defRetries)
        pollMs := Opt(step, "pollMs", defPollMs)
        runFn := step.run
        attempt := 0
        loop {
            attempt += 1
            ok := runFn()
            if (ok && step.HasOwnProp("done"))
                ok := WaitUntil(step.done, step.doneTimeoutMs, pollMs)

            if (ok)
                break

            if (attempt > retries) {
                Say(label ": step '" step.name "' FAILED after " attempt " attempt(s) - stopping")
                return false
            }
            Say(label ": step '" step.name "' failed (attempt " attempt "/" (retries + 1) ") - retrying fresh")
        }
    }
    return true
}

; Replaces GatherBankLoop. Runs RunSteps(opts.steps) forever (or
; until maxCycles), with session pacing checked at the cycle seam -
; after a fully successful cycle, before the maxCycles check, exactly
; where v7's GatherBankLoop checked it. A RunSteps failure (all
; retries on some step exhausted) stops the WHOLE loop and returns
; false - the caller's harness (Bot.ahk's WrapHandler) is what
; reports this as FAILED rather than a clean stop.
StepLoop(opts) {
    steps := opts.steps
    maxCycles := Opt(opts, "maxCycles", 0)
    retries := Opt(opts, "retries", 1)
    pollMs := Opt(opts, "pollMs", POLL_MS_DEFAULT)
    label := Opt(opts, "label", "StepLoop")

    breakChance := Opt(opts, "breakChance", 0)
    breakMs := Opt(opts, "breakMs", SESSION_BREAK_MS_DEFAULT)
    sessionExpired := opts.HasOwnProp("sessionLengthMs")
        ? NewSessionTimer({sessionLengthMs: opts.sessionLengthMs, label: label})
        : false

    cycle := 0
    loop {
        cycle += 1
        if (!RunSteps(steps, {retries: retries, pollMs: pollMs, label: label "-cycle" cycle}))
            return false

        if (sessionExpired && sessionExpired()) {
            Say(label ": session length elapsed after cycle " cycle " - stopping cleanly")
            return true
        }

        if (maxCycles > 0 && cycle >= maxCycles) {
            Say(label ": reached maxCycles (" maxCycles ") - stopping")
            return true
        }

        if (breakChance > 0)
            MaybeTakeBreak({chance: breakChance, breakMs: breakMs, label: label})
    }
}
