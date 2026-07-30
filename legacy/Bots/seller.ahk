; ============================================================
; v6 Seller helper - store sell + world-hop loop
;
; Loop: wait (silently - no action) for the store interface to open,
; click inventory slot 1 into it, instantly close the interface with
; Esc, wait for the interface to actually close, hop to a new world via
; the client's quick-world-switch hotkey (Ctrl+Shift+Right), wait for
; the world-switch confirmation overlay, confirm with Space, repeat
; forever until F6.
;
; UI-only interaction throughout (store overlay, inventory slot, client
; hotkeys) - CLICK_USE_CTRL is false, same reasoning as Sudoku's (a
; game-world click needs Ctrl to force-run/force-attack; a UI click
; doesn't).
;
; WHAT IT DOES
;   F5  = start the full loop, forever
;   F6  = request stop (interrupts instantly, mid-find or mid-wait)
;   F12 = exit the script
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "seller"
TrimLogOnStart()

; --- Step 1: store interface marker (appears once the shop opens). X/Y
; is the measured top-left CORNER, as-is - RegionAround (Lib\Steps.ahk)
; builds the search box directly from it, no center math needed here. ---
STORE_MARKER_IMAGE_PATH := A_ScriptDir "\..\Images\store-marker.png"
STORE_MARKER_W := 60
STORE_MARKER_H := 60
STORE_MARKER_TOL := 5
STORE_MARKER_TRANS_COLOR := "0x00FF00"   ; assumed - same convention as every other image
                                            ; asset in this project. Not yet confirmed via
                                            ; direct pixel inspection - verify if the search
                                            ; misbehaves.
STORE_MARKER_X := 731
STORE_MARKER_Y := 777
STORE_MARKER_WAIT_TIMEOUT_MS := 30000
STORE_MARKER_GONE_TIMEOUT_MS := 15000   ; give up if it never closes after Esc

; --- Step 2: which inventory slot to sell from each cycle. ---
SELL_SLOT := 1

; --- Step 4: world-switch confirmation overlay. Same corner convention
; as STORE_MARKER above. ---
WORLD_SWITCH_MARKER_IMAGE_PATH := A_ScriptDir "\..\Images\world-switch-marker.png"
WORLD_SWITCH_MARKER_W := 112
WORLD_SWITCH_MARKER_H := 110
WORLD_SWITCH_MARKER_TOL := 5
WORLD_SWITCH_MARKER_TRANS_COLOR := "0x00FF00"   ; assumed, same convention as above
WORLD_SWITCH_MARKER_X := 75
WORLD_SWITCH_MARKER_Y := 1135
WORLD_SWITCH_MARKER_WAIT_TIMEOUT_MS := 30000

CLICK_USE_CTRL := false   ; UI-only interaction, not a game-world object -
                          ; same reasoning as Sudoku's
POLL_MS := 150
SEARCH_MARGIN_PX := 40   ; passed into Lib\Steps.ahk's shared RegionAround
STEP_DELAY_MS := 150   ; settle between each numbered step below (and before
                        ; the next cycle's step 1) - tune live if any step
                        ; needs more

; One full sell -> close -> world-hop cycle.
SellCycle() {
    ; 1: wait silently (no action) for the store interface to appear
    storeRegion := RegionAround(STORE_MARKER_X, STORE_MARKER_Y, STORE_MARKER_W, STORE_MARKER_H, SEARCH_MARGIN_PX)
    Say("Seller: waiting for store marker")
    found := WaitUntil(() => FindImage(storeRegion[1], storeRegion[2], storeRegion[3], storeRegion[4],
        STORE_MARKER_IMAGE_PATH, STORE_MARKER_W, STORE_MARKER_H, STORE_MARKER_TOL, STORE_MARKER_TRANS_COLOR, &fx, &fy),
        STORE_MARKER_WAIT_TIMEOUT_MS, POLL_MS)
    if (!found) {
        Say("Seller: store marker never appeared within " STORE_MARKER_WAIT_TIMEOUT_MS "ms - stopping")
        return false
    }
    Pause(STEP_DELAY_MS)

    ; 2: click inventory slot SELL_SLOT, then INSTANTLY press Esc - no
    ; settle between them, as specified.
    SlotCenter(SELL_SLOT, &sx, &sy)
    Say("Seller: clicking inventory slot " SELL_SLOT " at " sx "," sy)
    ClickAt(sx, sy, CLICK_USE_CTRL)
    Send("{Esc}")
    Pause(STEP_DELAY_MS)

    ; 3: wait for the store marker to actually disappear before hopping -
    ; negated FindImage condition through WaitUntil, same shape Crafting's
    ; step 5 uses for "!SlotFull(...)".
    Say("Seller: waiting for store marker to close")
    gone := WaitUntil(() => !FindImage(storeRegion[1], storeRegion[2], storeRegion[3], storeRegion[4],
        STORE_MARKER_IMAGE_PATH, STORE_MARKER_W, STORE_MARKER_H, STORE_MARKER_TOL, STORE_MARKER_TRANS_COLOR, &fx, &fy),
        STORE_MARKER_GONE_TIMEOUT_MS, POLL_MS)
    if (!gone) {
        Say("Seller: store marker never closed within " STORE_MARKER_GONE_TIMEOUT_MS "ms - stopping")
        return false
    }
    Pause(STEP_DELAY_MS)

    ; 4: Ctrl+Shift+Right (client's quick-world-switch hotkey), then wait
    ; for its confirmation overlay.
    Send("^+{Right}")
    worldRegion := RegionAround(WORLD_SWITCH_MARKER_X, WORLD_SWITCH_MARKER_Y, WORLD_SWITCH_MARKER_W, WORLD_SWITCH_MARKER_H, SEARCH_MARGIN_PX)
    Say("Seller: waiting for world-switch marker")
    switched := WaitUntil(() => FindImage(worldRegion[1], worldRegion[2], worldRegion[3], worldRegion[4],
        WORLD_SWITCH_MARKER_IMAGE_PATH, WORLD_SWITCH_MARKER_W, WORLD_SWITCH_MARKER_H, WORLD_SWITCH_MARKER_TOL, WORLD_SWITCH_MARKER_TRANS_COLOR, &wx, &wy),
        WORLD_SWITCH_MARKER_WAIT_TIMEOUT_MS, POLL_MS)
    if (!switched) {
        Say("Seller: world-switch marker never appeared within " WORLD_SWITCH_MARKER_WAIT_TIMEOUT_MS "ms - stopping")
        return false
    }
    Pause(STEP_DELAY_MS)

    ; 5: confirm with Space
    Send("{Space}")
    Pause(STEP_DELAY_MS)

    return true
}

RunFullLoop() {
    global g_StopRequested
    g_StopRequested := false
    Say("Seller started")

    try {
        loop {
            if (!SellCycle()) {
                Say("Cycle failed - stopping (see log for which step)")
                break
            }
        }
    } catch BotStopped as e {
        Say("STOPPED by F6")
    }
}

F5:: RunFullLoop()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
; F12 (exit) is defined once in Lib\v6.ahk, shared by every bot.

LogLine("Script loaded. F5=start sell/world-hop loop  F6=stop  F12=exit.")
ToolTip("seller ready - F5 to start", 20, 20)
