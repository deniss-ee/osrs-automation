; ============================================================
; Waiter.ahk
; The ONLY place Sleep() is called anywhere in v4. Every pause a
; Phase needs goes through Waiter.After(profile, key), keyed into
; that bot's TimingProfile - no other class calls Sleep directly.
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
    ; isn't defined - no silent zero-delay fallback.
    ;
    ; Gotcha: this._jitterFn(a, b) is parsed by AHK v2 as a METHOD call on
    ; `this`, silently injecting `this` as a hidden extra argument - even
    ; though _jitterFn is a plain function, not a real method (throws "Too
    ; many parameters passed to function"). Fix: assign to a local first,
    ; then call it, so there's no implicit `this` injection.
    After(profile, key) {
        if (!profile.Has(key))
            throw Error("Waiter: no timing definition for key '" key "'")
        jitterFn := this._jitterFn
        ms := jitterFn(profile.BaseMs(key), profile.JitterPercent(key))
        Sleep(Max(0, Round(ms)))
    }

    ; Blocks for an explicit duration not tied to a named profile key -
    ; for library-level polling loops where the interval is a polling
    ; rate, not a bot-tunable action delay.
    ForMs(ms) {
        Sleep(Max(0, Round(ms)))
    }
}
