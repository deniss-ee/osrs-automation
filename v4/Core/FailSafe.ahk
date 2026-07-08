; ============================================================
; FailSafe.ahk
; Centralizes the "no progress for too long -> stop safely"
; rule so every Phase gets it for free instead of hand-rolling
; its own timeout/failure counter (legacy repeated this pattern
; ad hoc per-phase). Two independent tripwires:
; - per-phase timeout, measured from last ResetPhaseTimer() call
; - consecutive-failure counter, for "N failed attempts in a row"
;   checks that aren't naturally time-based (e.g. image never found)
; ============================================================

#Requires AutoHotkey v2.0

class FailSafe {
    __New(logger) {
        this._logger := logger
        this._phaseEnteredAt := 0
        this._phaseTimeoutMs := 0
        this._consecutiveFailures := 0
        this._maxConsecutiveFailures := 0
    }

    ; Call once when entering a new phase, with that phase's configured timeout.
    EnterPhase(phaseName, timeoutMs := 0) {
        this._phaseEnteredAt := A_TickCount
        this._phaseTimeoutMs := timeoutMs
        this._phaseName := phaseName
    }

    ; Call after real progress (a successful click, a confirmed state change) -
    ; NOT on every tick. Matches legacy's ResetPhaseTimer contract exactly:
    ; the timeout means "no progress for this long", not "total time in phase".
    ResetPhaseTimer(ctx) {
        this._phaseEnteredAt := A_TickCount
    }

    ; True once the current phase has gone longer than its timeout with no
    ; ResetPhaseTimer call. Engine checks this before ticking a phase.
    HasPhaseTimedOut() {
        if (this._phaseTimeoutMs <= 0)
            return false
        return (A_TickCount - this._phaseEnteredAt) > this._phaseTimeoutMs
    }

    ; Configure a consecutive-failure ceiling for the current phase (e.g.
    ; "give up after 3 clicks with no color change"). 0 = unlimited.
    SetFailureBudget(maxConsecutiveFailures) {
        this._maxConsecutiveFailures := maxConsecutiveFailures
        this._consecutiveFailures := 0
    }

    RecordFailure() {
        this._consecutiveFailures += 1
    }

    RecordSuccess() {
        this._consecutiveFailures := 0
    }

    HasExceededFailureBudget() {
        if (this._maxConsecutiveFailures <= 0)
            return false
        return this._consecutiveFailures >= this._maxConsecutiveFailures
    }

    ; Called by Engine when either tripwire fires. Logs and signals the
    ; caller to stop; does not itself perform a logout - that's a bot-level
    ; concern (some bots may want a real in-game logout sequence).
    Trip(reason) {
        this._logger.Log("FailSafe: tripped - " reason)
        return reason
    }
}
