; ============================================================
; v8 Lib\Session.ahk - session pacing (periodic short breaks +
; bounded overall session length)
;
; Ported verbatim from v7\Lib\Session.ahk. Rationale (unchanged):
; behavioral detection risk factors this project already covers
; (fixed click timing, straight mouse paths, click precision) vs the
; one gap - prolonged, repetitive, unbroken uptime. Both primitives
; pace exclusively through Pause() - F6-interruptible, BotStopped
; propagates untouched.
;
; Consumed by Run.ahk's StepLoop (this micro), which replaces v7's
; GatherBankLoop as the thing that wires these in at the cycle seam.
; ============================================================

SESSION_BREAK_MS_DEFAULT := [30000, 180000]
SESSION_LENGTH_MS_DEFAULT := [3600000, 7200000]

; Per-call probability-gated pause. Rolls Random(0,1) against
; opts.chance; on a hit, resolves breakMs (scalar or [min,max],
; rolled fresh here) and Pauses that long.
MaybeTakeBreak(opts) {
    chance := opts.chance
    breakMs := Opt(opts, "breakMs", SESSION_BREAK_MS_DEFAULT)
    label := Opt(opts, "label", "MaybeTakeBreak")

    if (Random(0.0, 1.0) > chance)
        return false

    ms := RollMs(breakMs)
    Say(label ": stepping away for a short break (" ms "ms / " Round(ms / 1000, 1) "s)")
    Pause(ms)
    Say(label ": break over, resuming")
    return true
}

; Maker: rolls a session length ONCE (scalar or [min,max]) and
; returns a closure the caller polls repeatedly to check expiry.
NewSessionTimer(opts) {
    sessionLengthMs := opts.sessionLengthMs
    label := Opt(opts, "label", "SessionTimer")

    ms := RollMs(sessionLengthMs)
    startedAt := A_TickCount
    Say(label ": session length rolled at " ms "ms / " Round(ms / 60000, 1) " min")

    return SessionExpired

    SessionExpired() {
        return (A_TickCount - startedAt) >= ms
    }
}
