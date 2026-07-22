; ============================================================
; v7 micro 09 - raw key/chord send (PressKey)
;
; Brand-new primitive (v6 never built this - Act.ahk explicitly
; deferred it, and crafting/smithing/seller/sudoku all fell back to
; bare Send("{Space}")/Send("{Esc}")/Send("^+{Right}") instead).
; PressKey(keys, preDelayMs, postDelayMs) wraps Send with the same
; pre/post-delay contract every action function gets, plus the same
; modifier-bleed guard ClickAt uses (ReleasePendingModifiersNow at its
; own start).
;
; EXIT KEY IS F12, NOT Esc (exception to the usual micro convention):
; this micro's whole job is proving PressKey can send a real Esc as a
; game action (seller.ahk's click-then-immediate-Esc sequence) - if
; this script ALSO bound Esc:: as its exit hotkey, sending {Esc} as a
; test action would likely re-trigger its own exit hotkey and close
; the script mid-test. F12 sidesteps that collision entirely (matches
; how real bots exit, per project convention - Esc is reserved for
; micros that never send a real Esc, which this one isn't).
;
; WHAT IT DOES
;   F5  = PressKey(TEST_KEYS) - plain key/text send. Focus a text
;         field (e.g. RuneLite's chatbox) first, then press F5, and
;         confirm TEST_KEYS actually appears/registers there.
;   F7  = PressKey(CHORD_KEYS) - chord send (default "^a" - Ctrl+A
;         select-all in a focused text field; swap for any chord you
;         can visually verify, e.g. a client hotkey).
;   F8  = the REAL pattern every bot actually uses: confirm a known
;         marker is present (FindImage, same MARKER_X/Y+IMAGE_* check
;         as micro 07 - reused here, not re-invented) THEN immediately
;         PressKey("{Esc}") - zero gap between the confirmation and the
;         key send - THEN re-check the same marker is now GONE, proving
;         Esc actually closed whatever was open. Not a blind click at
;         an arbitrary point - there's no bot in this codebase that
;         clicks-then-Escs with no precondition; Esc always follows a
;         confirmed state, e.g. "the deposit box is open".
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   F12 = exit the script (NOT Esc - see note above)
;
; LIVE CONFIRM:
;   1. F5 with the game chat input focused - confirm TEST_KEYS appears.
;   2. F7 with a text field focused - confirm the chord's effect (e.g.
;      Ctrl+A selecting existing text) is visible.
;   3. Open whatever's behind MARKER_X/Y (a bank/deposit interface,
;      etc.), press F8 - confirm it reports PRESENT, sends Esc, then
;      confirms GONE. Press F8 again with nothing open - confirm it
;      correctly reports "marker not present, skipping Esc" instead of
;      sending Esc unconditionally.
;   4. Fire F7 (a Ctrl chord) right before F8 - confirm PressKey's own
;      guard releases any still-pending modifier first (same
;      ReleasePendingModifiersNow check ClickAt uses), so Esc doesn't
;      get sent as Ctrl+Esc by accident.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "09-press-key"

; ======= EDIT THESE FOR YOUR TEST =======================================
TEST_KEYS := "{Space}"   ; plain key/text to send - swap for anything visually verifiable
CHORD_KEYS := "^a"       ; a chord to send - swap for a client hotkey you can verify

; The precondition marker for F8 - same asset/position shape as micro
; 07 (corner-measured, exact box, no RegionAround padding for a PNG).
; Whatever this marker represents (a deposit box, a menu, any
; dismissible UI) is what Esc is expected to close.
ESC_IMAGE_PATH := A_ScriptDir "\..\Images\deposit-motherlode.png"
ESC_IMAGE_W := 80
ESC_IMAGE_H := 72
ESC_IMAGE_TOL := 5
ESC_TRANS_COLOR := "0x00FF00"
ESC_MARKER_X := 775
ESC_MARKER_Y := 765
ESC_MARGIN_PX := 0
; ========================================================================

escRegion := RegionAround(ESC_MARKER_X, ESC_MARKER_Y, ESC_IMAGE_W, ESC_IMAGE_H, ESC_MARGIN_PX)
ESC_REGION_X1 := escRegion[1]
ESC_REGION_Y1 := escRegion[2]
ESC_REGION_X2 := escRegion[3]
ESC_REGION_Y2 := escRegion[4]

F5:: RunPlainKey()
F7:: RunChordKey()
F8:: RunConfirmThenEsc()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
F12:: {
    LogLine("F12 pressed - exiting")
    ExitApp()
}

RunPlainKey() {
    global g_StopRequested
    g_StopRequested := false

    LogLine("PressKey (plain) started: keys=" TEST_KEYS)
    PressKey(TEST_KEYS)
    msg := "Sent " TEST_KEYS " - check it registered in your focused field"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

RunChordKey() {
    global g_StopRequested
    g_StopRequested := false

    LogLine("PressKey (chord) started: keys=" CHORD_KEYS)
    PressKey(CHORD_KEYS)
    msg := "Sent " CHORD_KEYS " - check its effect registered"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

RunConfirmThenEsc() {
    global g_StopRequested
    g_StopRequested := false

    LogLine("Confirm-then-Esc started: checking " ESC_IMAGE_PATH " at " ESC_MARKER_X "," ESC_MARKER_Y)
    t0 := A_TickCount

    present := FindImage(ESC_REGION_X1, ESC_REGION_Y1, ESC_REGION_X2, ESC_REGION_Y2,
        ESC_IMAGE_PATH, ESC_IMAGE_W, ESC_IMAGE_H, ESC_IMAGE_TOL, ESC_TRANS_COLOR, &cx, &cy)

    if (!present) {
        msg := "Marker not present - skipping Esc (nothing to close)"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }

    LogLine("Marker PRESENT at " cx "," cy " - sending Esc immediately (zero gap)")
    PressKey("{Esc}", 0, 0)

    stillPresent := FindImage(ESC_REGION_X1, ESC_REGION_Y1, ESC_REGION_X2, ESC_REGION_Y2,
        ESC_IMAGE_PATH, ESC_IMAGE_W, ESC_IMAGE_H, ESC_IMAGE_TOL, ESC_TRANS_COLOR, &cx2, &cy2)

    elapsedMs := A_TickCount - t0
    msg := stillPresent
        ? "STILL PRESENT after Esc - did not close (" elapsedMs " ms)"
        : "GONE after Esc - closed successfully (" elapsedMs " ms)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=plain key  F7=chord  F8=confirm-then-Esc  F6=request stop  F12=exit."
    . " TestKeys=" TEST_KEYS " ChordKeys=" CHORD_KEYS " EscMarker=" ESC_MARKER_X "," ESC_MARKER_Y)
ToolTip("micro 09 ready - F5/F7/F8 to test, F12 to exit", 20, 20)
