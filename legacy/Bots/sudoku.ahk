; ============================================================
; v6 Sudoku bot - resolver part (menu clearing)
;
; Clears a fixed search zone of repeating slot icons, once per menu
; tab (2x4 = 8 tabs, clicked in order), then clicks the open button
; once and stops. NOT included yet (later parts): actual sudoku-
; solving logic, dialogue automation - this is just the prep step
; that gets the puzzle interface into a clean, open state.
;
; Built from Lib primitives (FindImage, ClickAt, Pause, Lib\Find.ahk/
; Lib\Act.ahk/Lib\Core.ahk) but the clearing loop itself is NOT built
; on Lib\Steps.ahk's FindAndClickImage - that composite is for "wait
; up to N ms for ONE appearance, then click it" (polls over time,
; times out if nothing shows up). This search zone is a static,
; non-respawning field of icons: the correct stop condition is "a
; single search attempt right now found nothing," not a timeout. So
; ClearSearchZone() below is a hand-rolled loop calling FindImage
; directly - only one caller so far, so per this project's rule
; against speculative promotion it stays local to this file.
;
; WHAT IT DOES
;   F5  = start: clear the already-selected default screen first (no
;         tab click), then click each of the 8 menu tabs in order,
;         clearing its zone before moving to the next, then click the
;         open button once
;   F6  = request stop (interrupts instantly, mid-clear)
;   F12 = exit the script
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "sudoku"
TrimLogOnStart()

; ======= EDIT THESE FOR YOUR TEST =======================================
; --- Search zone (whole area where slot icons can appear) ---
SEARCH_X1 := 451, SEARCH_Y1 := 229
SEARCH_X2 := 451 + 708, SEARCH_Y2 := 229 + 636

; --- Slot icon (FindImage - white transparency, unlike sack.png/
; deposit-motherlode.png's green) ---
SLOT_IMAGE_PATH := A_ScriptDir "\..\Images\sudoku-slot.png"
SLOT_IMAGE_W := 72
SLOT_IMAGE_H := 64
SLOT_IMAGE_TOL := 5
SLOT_TRANS_COLOR := "0xFFFFFF"

CLICK_USE_CTRL := false   ; UI-only interaction, not a game-world object -
                          ; different default than Woodcutting/Motherlode's true

; Settle delays - starting points, tune live from the log like every
; other settle delay added this project (SACK_CLICK_SETTLE_MS etc.)
SLOT_CLICK_SETTLE_MS := 50   ; after clicking a slot, before re-searching
MENU_CLICK_SETTLE_MS := 50   ; after switching menu tabs, before searching its content

MAX_CLEAR_ITERATIONS := 200   ; safety cap per menu item - fail clean+log
                               ; instead of spinning forever if a click
                               ; stops registering

; --- Menu grid (2 cols x 4 rows = 8 tabs), CORNER convention (matches
; Lib\Inv.ahk's INV_FIRST_X/Y - a corner + half-size click-center math,
; not raw click points) ---
MENU_FIRST_X := 275, MENU_FIRST_Y := 415
MENU_COLS := 2, MENU_ROWS := 4
MENU_ITEM_W := 72, MENU_ITEM_H := 64
MENU_GAP_X := 4, MENU_GAP_Y := 10

; --- Open button (fixed point, no detection - unlike the slot icons).
; X/Y is the measured top-left CORNER, as-is - the click center is
; computed at the point of use via CenterX/CenterY (see RunSudokuResolver). ---
OPEN_BUTTON_X := 269, OPEN_BUTTON_Y := 711
OPEN_BUTTON_W := 160, OPEN_BUTTON_H := 50
; ========================================================================

F5:: RunSudokuResolver()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
; F12 (exit) is defined once in Lib\v6.ahk, shared by every bot.

RunSudokuResolver() {
    global g_StopRequested
    g_StopRequested := false

    Say("Sudoku resolver started: " (MENU_COLS * MENU_ROWS) " menu tabs")

    try {
        SudokuLoop()
    } catch BotStopped as e {
        Say("STOPPED by F6")
    }
}

; Clicks each of the 8 menu tabs in order, clearing that tab's search
; zone before moving to the next, then clicks the open button once.
;
; BUG FIXED (2026-07-20): the menu is already selected/showing content
; when the interface opens - clicking tab 1 before ever searching
; missed whatever was already visible on that default "screen 0"
; (something about the click reset/shifted the view before it got
; cleared). Fixed by clearing the zone ONCE up front, with no tab
; click, before entering the tab loop - only THEN does the loop click
; tab 1 (and tabs 2-8) and clear each.
SudokuLoop() {
    Say("Sudoku: clearing already-selected screen before any tab click")
    if (!ClearSearchZone()) {
        Say("Sudoku: stopping (see log for why)")
        return
    }

    total := MENU_COLS * MENU_ROWS
    loop total {
        itemIndex := A_Index
        MenuItemCorner(itemIndex, &mx, &my)
        clickX := CenterX(mx, MENU_ITEM_W)
        clickY := CenterY(my, MENU_ITEM_H)

        Say("Sudoku: clicking menu item " itemIndex "/" total " at " clickX "," clickY)
        ClickAt(clickX, clickY, CLICK_USE_CTRL)
        Pause(MENU_CLICK_SETTLE_MS)

        if (!ClearSearchZone()) {
            Say("Sudoku: stopping (see log for why)")
            return
        }
    }

    openX := CenterX(OPEN_BUTTON_X, OPEN_BUTTON_W)
    openY := CenterY(OPEN_BUTTON_Y, OPEN_BUTTON_H)
    Say("Sudoku: all menu items cleared - clicking open button at " openX "," openY)
    ClickAt(openX, openY, CLICK_USE_CTRL)
    Say("Sudoku: done")
}

; Repeatedly finds+clicks every instance of the slot icon within the
; search zone until a single search attempt finds nothing - not a
; timeout-based wait, since nothing here respawns. Returns false only
; if MAX_CLEAR_ITERATIONS is hit (a click probably isn't registering),
; a clean stop rather than spinning forever. Throws BotStopped
; (propagated from Pause) if the user hits F6 mid-clear - never
; swallowed, same as every wait in this codebase.
ClearSearchZone() {
    loop MAX_CLEAR_ITERATIONS {
        found := FindImage(SEARCH_X1, SEARCH_Y1, SEARCH_X2, SEARCH_Y2,
            SLOT_IMAGE_PATH, SLOT_IMAGE_W, SLOT_IMAGE_H, SLOT_IMAGE_TOL, SLOT_TRANS_COLOR, &cx, &cy)
        if (!found) {
            Say("Sudoku: zone clear (" (A_Index - 1) " slot" ((A_Index - 1) = 1 ? "" : "s") " clicked)")
            return true
        }

        Say("Sudoku: clicking slot at " cx "," cy)
        ClickAt(cx, cy, CLICK_USE_CTRL)
        Pause(SLOT_CLICK_SETTLE_MS)
    }

    Say("Sudoku: MAX_CLEAR_ITERATIONS (" MAX_CLEAR_ITERATIONS ") hit - a click may not be registering")
    return false
}

; 1-based, row-major (left-to-right, top-to-bottom) menu index -> that
; item's top-left CORNER. Same col/row/gap formula as Lib\Inv.ahk's
; SlotCorner, sized for this bot's 2x4 grid instead - not promoted to
; Lib since it's a different grid shape/constants with only one caller.
MenuItemCorner(itemIndex, &x, &y) {
    total := MENU_COLS * MENU_ROWS
    if (itemIndex < 1 || itemIndex > total)
        throw ValueError("MenuItemCorner: itemIndex " itemIndex " out of range (1.." total ")")

    col := Mod(itemIndex - 1, MENU_COLS)
    row := (itemIndex - 1) // MENU_COLS

    x := MENU_FIRST_X + col * (MENU_ITEM_W + MENU_GAP_X)
    y := MENU_FIRST_Y + row * (MENU_ITEM_H + MENU_GAP_Y)
}

LogLine("Script loaded. F5=start resolver  F6=stop  F12=exit.")
ToolTip("sudoku resolver ready - F5 to start", 20, 20)
