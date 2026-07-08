; ============================================================
; Config.ahk
; Typed .ini accessor + per-bot schema validation, merged from
; the originally-proposed ConfigLoader/ScriptConfig split (see
; plan trim). A bot declares every key it needs up front in a
; schema Map; Load() throws at startup if any declared key is
; missing from .ini - this is the direct fix for legacy's
; silent config/code default drift (e.g. preBankClickSettleMs
; never appearing in the .ini at all, mineStableTicks disagreeing
; between code default and calibrated ini value).
; ============================================================

#Requires AutoHotkey v2.0

#Include ..\Timing\TimingProfile.ahk

class Config {
    ; schema: Map of key -> {section, type} where type is "int"|"float"|"color"|"str".
    ; timingSchema: Map of timing-key -> {section, baseMsKey, jitterPercentKey?}.
    __New(iniPath, schema, timingSchema) {
        this._iniPath := iniPath
        this._schema := schema
        this._timingSchema := timingSchema
        this._values := Map()
    }

    ; Reads every declared key from .ini once. Throws immediately listing
    ; ALL missing keys (not just the first) so a bot author fixes the ini
    ; in one pass instead of one error at a time.
    Load() {
        missing := []
        for key, spec in this._schema {
            raw := IniRead(this._iniPath, spec["section"], key, "__MISSING__")
            if (raw = "__MISSING__") {
                missing.Push(spec["section"] "/" key)
                continue
            }
            this._values[key] := this._Coerce(raw, spec["type"])
        }

        delays := Map()
        for timingKey, spec in this._timingSchema {
            raw := IniRead(this._iniPath, spec["section"], spec["baseMsKey"], "__MISSING__")
            if (raw = "__MISSING__") {
                missing.Push(spec["section"] "/" spec["baseMsKey"])
                continue
            }
            entry := Map("baseMs", Integer(raw))
            if (spec.Has("jitterPercentKey")) {
                jRaw := IniRead(this._iniPath, spec["section"], spec["jitterPercentKey"], "0")
                entry["jitterPercent"] := Integer(jRaw)
            }
            delays[timingKey] := entry
        }
        this.timing := TimingProfile(delays)

        if (missing.Length > 0)
            throw Error("Config: missing required .ini keys - " this._Join(missing, ", "))
    }

    Get(key) => this._values[key]

    _Coerce(raw, type) {
        switch type {
            case "int": return Integer(raw)
            case "float": return Float(raw)
            case "color": return Integer(raw)
            default: return raw
        }
    }

    _Join(arr, sep) {
        out := ""
        for i, v in arr
            out .= (i > 1 ? sep : "") v
        return out
    }
}
