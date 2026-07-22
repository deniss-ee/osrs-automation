; ============================================================
; v7 micro 10 - right-click a known block -> context menu -> click a
; specific entry
;
; Brand-new primitive (gap primitive from TEMPLATES.md's AutoFighterLoot
; spec - no v6 bot ever built this). RightClickMenuItem(x, y, ...)
; right-clicks a point, waits for a specific menu entry image to appear
; in a fixed searchBoxSize box CENTERED on the click point, and
; left-clicks its center. On a miss, it sends Esc to close the menu so
; it doesn't linger open.
;
; The right-click TARGET reuses micro 06's exact block config (same
; TARGET_COLORS/MARKER_X/MARKER_Y/BLOCK_W/BLOCK_H, same CenterX/CenterY
; derivation) - confirm the block is there via IsAnyColorAt first
; (same check as 06's F5), THEN right-click its center, THEN search for
; the menu item. Not a fresh/arbitrary point - this is "right-click a
; thing we already know how to find."
;
; EXIT KEY IS F12, NOT Esc (same reason as micro 09): RightClickMenuItem
; sends a real Esc internally on a not-found path, which would collide
; with an Esc:: exit hotkey in this same script.
;
; WHAT IT DOES
;   F5  = confirm the block (IsAnyColorAt at CENTER_X,CENTER_Y) - abort
;         if it's not there. If present, right-click it, then search a
;         512x512 box centered on that same point for
;         li_bank-deposit-box.png; click it (Ctrl-held if USE_CTRL,
;         forcing a run instead of a walk) if found within
;         WAIT_TIMEOUT_MS. Reports FOUND+clicked or NOT FOUND (+Esc
;         sent to close the menu).
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   F12 = exit the script (NOT Esc - see note above)
;
; LIVE CONFIRM:
;   1. With the block present AND its real right-click menu showing the
;      deposit-box entry, press F5 - confirm it's found and clicked.
;   2. With the block present but the menu NOT showing that entry (or
;      close the menu quickly before the search catches it), confirm
;      NOT FOUND fires and Esc closes the menu.
;   3. With the block NOT present at all, confirm F5 aborts before even
;      right-clicking (no point right-clicking nothing).
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "10-context-menu-click"

; ======= EDIT THESE FOR YOUR TEST =======================================
; Same block config as micro 06 - the right-click TARGET.
TARGET_COLORS := [0xCC5D02]
COLOR_TOL := 5
BLOCK_W := 17
BLOCK_H := 17
MARKER_X := 1630
MARKER_Y := 884

; The menu item to find after right-clicking the block above.
ITEM_IMAGE_PATH := A_ScriptDir "\..\Images\li_bank-deposit-box.png"
ITEM_IMAGE_W := 332
ITEM_IMAGE_H := 30
ITEM_TOL := 10
ITEM_TRANS_COLOR := ""   ; "" = no transparency; set "0x00FF00" if painted with a green bg

SEARCH_BOX_SIZE := 512   ; fixed box centered on the right-click point (not item-size-derived)
WAIT_TIMEOUT_MS := 2000  ; how long to wait for the menu entry to appear

; menuSettleMs is a NEW knob being actively calibrated right now (gap
; after the right-click, before the first menu-item search attempt) -
; exposed here for tuning, same reasoning micro 08 exposed settle/hold
; while THEY were being calibrated. settleMs itself is NOT redeclared -
; RightClickMenuItem's own default (100) applies automatically.
MENU_SETTLE_MS := 100

; Force-run (Ctrl-held) on the menu-item click ONLY - not the
; right-click, which has no force-run meaning in OSRS. Selecting this
; menu item may make the character walk/run over to reach whatever it
; acts on; USE_CTRL=true makes that a run instead of a walk.
USE_CTRL := true
; ========================================================================

; Derived center - same convention as every other micro (CenterX/CenterY,
; never a hand-typed center constant).
CENTER_X := CenterX(MARKER_X, BLOCK_W)
CENTER_Y := CenterY(MARKER_Y, BLOCK_H)

F5:: RunTest()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
F12:: {
    LogLine("F12 pressed - exiting")
    ExitApp()
}

RunTest() {
    global g_StopRequested
    g_StopRequested := false

    LogLine("Test started: confirming block at " CENTER_X "," CENTER_Y " before right-clicking")

    isThere := IsAnyColorAt(CENTER_X, CENTER_Y, TARGET_COLORS, COLOR_TOL, &foundColor)
    if (!isThere) {
        msg := "Block not present at " CENTER_X "," CENTER_Y " - aborting (nothing to right-click)"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }

    LogLine("Block confirmed (" HexColor(foundColor) ") - right-clicking " CENTER_X "," CENTER_Y)
    t0 := A_TickCount

    found := RightClickMenuItem(CENTER_X, CENTER_Y, ITEM_IMAGE_PATH, ITEM_IMAGE_W, ITEM_IMAGE_H,
        ITEM_TOL, ITEM_TRANS_COLOR, WAIT_TIMEOUT_MS, SEARCH_BOX_SIZE, , MENU_SETTLE_MS, USE_CTRL)

    elapsedMs := A_TickCount - t0
    msg := found
        ? "FOUND and clicked menu item (" elapsedMs " ms)"
        : "NOT FOUND - menu item never appeared, Esc sent to close menu (" elapsedMs " ms)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=confirm block+right-click+find menu item  F6=request stop  F12=exit."
    . " Block=" CENTER_X "," CENTER_Y " Item=" ITEM_IMAGE_PATH)
ToolTip("micro 10 ready - F5 to test, F12 to exit", 20, 20)
