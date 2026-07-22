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

; Shared "exit script" hotkey - promoted here (2026-07-22) once found
; byte-identical across every bot (autoclicker/crafting/motherlode2/
; smithing/sudoku/woodcutting all had their own copy of the same 4 lines,
; bound to Esc). A same-day hold-to-exit variant (bound to Esc, requiring
; a ~1s hold) was tried and reverted: confirmed live, with Seller running,
; a plain Esc tap no longer did anything - reverting to instant tap-to-
; exit, but moved to F12 instead of Esc, since Seller sends a real Esc
; keypress as a normal in-game action (closing the store interface) and
; double-booking the same key for both purposes is what caused the
; original confusion.
F12:: {
    LogLine("F12 pressed - exiting")
    ExitApp()
}
