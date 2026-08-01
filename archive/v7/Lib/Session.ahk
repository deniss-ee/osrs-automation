; ============================================================
; v7 Lib\Session.ahk - session pacing (periodic short breaks +
; bounded overall session length), standard #30
;
; The one commonly-cited OSRS bot detection vector this codebase had
; zero coverage for: every other vector (click timing randomization,
; curved mouse paths, click-point jitter) is already handled in
; Act.ahk/Steps.ahk. "Prolonged, repetitive action with no breaks" and
; unbounded uptime are not. This file is deliberately small and does
; NOT touch mouse movement or click behavior at all - pure timing.
;
; Both primitives here pace EXCLUSIVELY through Pause() (Core.ahk) -
; F6-interruptible, BotStopped propagates, never caught here. Neither
; primitive does anything unless a caller opts in; there is no global
; "always on" switch.
;
; DEFAULTS (used only as an Opt() fallback when a caller opts in but
; omits the duration - the OPT-IN ITSELF is always caller-driven, these
; are not auto-enabled):
;  - SESSION_BREAK_MS_DEFAULT [30000, 180000] (30s-3min): a "stepped
;    away for a moment" pause, not a meal break.
;  - SESSION_LENGTH_MS_DEFAULT [3600000, 7200000] (1-2h): the article's
;    suggested session cap; oldschoolscripts.com's most-cited figure is
;    activity-dependent (1-3h, shorter for high-ban-rate skills like
;    Agility) - so this is a starting default, not a fixed rule. A
;    real bot should set its own sessionLengthMs per-activity, not rely
;    on this default long-term.
; ============================================================

SESSION_BREAK_MS_DEFAULT := [30000, 180000]
SESSION_LENGTH_MS_DEFAULT := [3600000, 7200000]

; ---------- periodic short breaks ----------
;
; Rolls ONE chance check per call; on a hit, pauses for a randomized
; duration and returns true. Caller doesn't need to branch on the
; result - call it, keep going either way. Same "scalar or [min,max]
; array, rolled fresh at the point of use" idiom as TrackAndClick's
; reclickAfterMs/NextReclickThreshold (Lib\Steps.ahk) - not reusing
; that name, this is a distinct concept (a probability roll gating a
; pause, not a re-roll on every miss).
;
; opts: chance (0..1, required); breakMs (number or [min,max],
;   default SESSION_BREAK_MS_DEFAULT), label.
MaybeTakeBreak(opts) {
    chance := opts.chance
    breakMs := Opt(opts, "breakMs", SESSION_BREAK_MS_DEFAULT)
    label := Opt(opts, "label", "MaybeTakeBreak")

    if (Random(0.0, 1.0) > chance)
        return false

    ms := (breakMs is Array) ? Random(breakMs[1], breakMs[2]) : breakMs
    Say(label ": stepping away for a short break (" Round(ms / 1000) "s)")
    Pause(ms)
    Say(label ": break over, resuming")
    return true
}

; ---------- bounded overall session length ----------
;
; Rolls the session length ONCE (a real session has one length, decided
; when you sit down - not re-rolled per check) and returns a closure
; (same "maker" shape as VerifySlotsAndDrop, Lib\Steps.ahk) the caller
; polls at its own cadence. True once the rolled duration has elapsed
; since this was created.
;
; opts: sessionLengthMs (number or [min,max], required); label.
NewSessionTimer(opts) {
    sessionLengthMs := opts.sessionLengthMs
    label := Opt(opts, "label", "SessionTimer")

    ms := (sessionLengthMs is Array) ? Random(sessionLengthMs[1], sessionLengthMs[2]) : sessionLengthMs
    startedAt := A_TickCount
    Say(label ": session length rolled at " Round(ms / 60000) " min")

    return SessionExpired

    SessionExpired() {
        return (A_TickCount - startedAt) >= ms
    }
}
