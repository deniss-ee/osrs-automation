; ============================================================
; Waiter.ahk
; The ONLY place Sleep() is called anywhere in v4. Every pause
; a Phase needs - pre-click settle, post-action cooldown,
; between-phase grace - goes through Waiter.After(profile, key),
; keyed into that bot's TimingProfile. This is the structural
; fix for legacy's inline Sleep() calls scattered through phase
; functions (auto-motherlode-v2.ahk lines 386/409/449/466/499):
; no other v4 class imports or calls Sleep, so the anti-pattern
; can't recur by accident.
; ============================================================

#Requires AutoHotkey v2.0

#Include TimingProfile.ahk

class Waiter {
    __New(jitterFn := "") {
        ; Optional jitter function (baseMs, jitterPercent) => ms, e.g. a
        ; Humanizer method. Defaults to no jitter (returns baseMs as-is).
        this._jitterFn := jitterFn != "" ? jitterFn : (baseMs, jitterPercent) => baseMs
    }

    ; Blocks for the duration named `key` in `profile`. Throws if the key
    ; isn't defined - there is no silent zero-delay fallback, matching the
    ; "config is the single source of truth" rule.
    After(profile, key) {
        if (!profile.Has(key))
            throw Error("Waiter: no timing definition for key '" key "'")
        ms := this._jitterFn(profile.BaseMs(key), profile.JitterPercent(key))
        Sleep(Max(0, Round(ms)))
    }

    ; Blocks for an explicit duration not tied to a named profile key -
    ; reserved for library-level polling loops (e.g. inside a StaticAnchor
    ; WaitFor implementation) where the interval is the polling rate, not a
    ; bot-tunable action delay.
    ForMs(ms) {
        Sleep(Max(0, Round(ms)))
    }
}
