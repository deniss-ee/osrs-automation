; ============================================================
; TimingProfile.ahk
; Named delay definitions for one bot, loaded from its .ini.
; Every duration a Phase waits on is looked up here by semantic
; key - never a bare number in phase code. A missing key is a
; startup error, not a silent fallback.
; ============================================================

#Requires AutoHotkey v2.0

class TimingProfile {
    __New(delaysMap) {
        this._delays := delaysMap   ; Map: key -> {baseMs, jitterPercent}
    }

    ; Used by Config schema validation, not by Phase code.
    Has(key) => this._delays.Has(key)

    BaseMs(key) => this._delays[key]["baseMs"]

    JitterPercent(key) => this._delays[key].Has("jitterPercent") ? this._delays[key]["jitterPercent"] : 0
}
