; ============================================================
; FailSafe.ahk
; "No progress for too long -> stop safely", shared by every
; Phase. Two independent tripwires:
; - per-phase timeout, measured from the last ResetPhaseTimer() call
; - consecutive-failure counter, for non-time-based failure checks
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

    ; Call once when entering a new phase, with its configured timeout.
    EnterPhase(phaseName, timeoutMs := 0) {
        this._phaseEnteredAt := A_TickCount
        this._phaseTimeoutMs := timeoutMs
        this._phaseName := phaseName
    }

    ; Call after real progress (a click, a confirmed state change) - NOT on
    ; every tick. The timeout means "no progress this long", not "total time".
    ResetPhaseTimer(ctx) {
        this._phaseEnteredAt := A_TickCount
    }

    ; True once the phase has gone longer than its timeout with no
    ; ResetPhaseTimer call. Engine checks this before ticking a phase.
    HasPhaseTimedOut() {
        if (this._phaseTimeoutMs <= 0)
            return false
        return (A_TickCount - this._phaseEnteredAt) > this._phaseTimeoutMs
    }

    ; Consecutive-failure ceiling for the current phase. 0 = unlimited.
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

    ; Called by Engine when either tripwire fires. Logs and returns the
    ; reason; a real logout (if wanted) is a bot-level concern.
    Trip(reason) {
        this._logger.Log("FailSafe: tripped - " reason)
        return reason
    }
}
