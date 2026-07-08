; ============================================================
; TimingProfile.ahk
; Named delay definitions for one bot, loaded from that bot's
; .ini. Every duration a Phase ever waits on is looked up here
; by semantic key ("mineClickCooldown", "sackPreClick") - never
; a bare number typed into phase code. A missing key is a
; config error caught at startup by Config, not a silent
; fallback (see ruleset 3.6).
; ============================================================

#Requires AutoHotkey v2.0

class TimingProfile {
    __New(delaysMap) {
        this._delays := delaysMap   ; Map: key -> {baseMs, jitterPercent}
    }

    ; Returns true if this profile has a definition for key - used by
    ; Config schema validation, not by Phase code.
    Has(key) => this._delays.Has(key)

    BaseMs(key) => this._delays[key]["baseMs"]

    JitterPercent(key) => this._delays[key].Has("jitterPercent") ? this._delays[key]["jitterPercent"] : 0
}
