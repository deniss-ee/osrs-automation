; ============================================================
; v6 Lib\v6.ahk - umbrella include
;
; Bots and micros #Include only this file, never the individual
; Lib\*.ahk files directly - keeps the include list in one place.
; Order matters: later files call functions defined in earlier ones
; (Find/Act/Inv are used by Steps; Core's LogLine/Say are used by all).
;
; Config.ahk is not included here yet - it doesn't exist yet (see
; the plan file's Stage 2 notes: no micro tested INI loading, so it's
; designed alongside the first real bot, not promoted from a micro).
; ============================================================

#Include Core.ahk
#Include Find.ahk
#Include Act.ahk
#Include Inv.ahk
#Include Steps.ahk
