; ============================================================
; v7 micro 22 - the Mark-of-Grace pattern (PickupAppeared)
;
; Port from v6 Lib\Steps.ahk with clickOffsetX/Y REMOVED - v7's hard
; rule is no click-offset compensation constants anywhere; the click
; lands directly at the found image's center. Waits for a transient
; item to appear on screen, clicks it, then confirms the pickup
; actually registered via a before/after pixel-box snapshot diff
; (TakeSnapshot/HasChanged, micro 14) around a watched inventory slot -
; NOT by re-searching for the image again, since a picked-up item is
; gone, not moved, so there's nothing left to re-find.
;
; WHAT IT DOES
;   F5  = PickupAppeared: wait for IMAGE_PATH to appear anywhere in
;         REGION, click it directly at its found center, then confirm
;         the pickup by watching CONFIRM_SLOT for any change
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   Esc = exit the script
;
; LIVE CONFIRM: with the image NOT currently visible, press F5, then
; make it appear somewhere within REGION before APPEAR_TIMEOUT_MS -
; confirm it gets found+clicked, and CONFIRM_SLOT (which should receive
; the picked-up item, or otherwise visibly change) is detected as
; changed. Also test the image never appearing (NEVER APPEARED,
; timeout) and the image appearing+being clicked but the confirm slot
; never changing (CLICKED but NOT CONFIRMED, e.g. a miss-click or the
; item vanishing before pickup).
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "22-pickup-appeared"

; ======= EDIT THESE FOR YOUR TEST =======================================
; Same test asset micros 07/16 use - swap for a real transient-pickup
; image (e.g. a ground item) when testing against the real thing.
IMAGE_PATH := A_ScriptDir "\..\Images\air-rune.png"
IMAGE_W := 78
IMAGE_H := 20
IMAGE_TOL := 5
TRANS_COLOR := "0x00FF00"

; Search area - corner + size, same AREA_X/Y/W/H convention as micro 04.
AREA_X := 1080
AREA_Y := 520
AREA_W := 160
AREA_H := 100

APPEAR_TIMEOUT_MS := 15000
CLICK_USE_CTRL := true

; Confirm box - watch a specific inventory slot (via Lib\Inv.ahk
; SlotCorner) for ANY change after the click, same convention micro 14
; established. Swap CONFIRM_SLOT for whichever slot should receive the
; picked-up item.
CONFIRM_SLOT := 1
CHANGE_TOL := 10
TARGET_SAMPLES := 50
CONFIRM_TIMEOUT_MS := 10000

POLL_MS := 100
; ========================================================================

region := RegionAround(AREA_X, AREA_Y, AREA_W, AREA_H, 0)
SlotCorner(CONFIRM_SLOT, &confirmBoxX, &confirmBoxY)

F5:: RunPickupAppeared()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunPickupAppeared() {
    global g_StopRequested, region, confirmBoxX, confirmBoxY
    g_StopRequested := false

    Say("micro22: waiting for pickup image to appear")

    t0 := A_TickCount
    try {
        result := PickupAppeared({
            imagePath: IMAGE_PATH, imageW: IMAGE_W, imageH: IMAGE_H,
            imageTol: IMAGE_TOL, transColor: TRANS_COLOR,
            region: region, appearTimeoutMs: APPEAR_TIMEOUT_MS,
            ctrl: CLICK_USE_CTRL,
            confirmBox: {x: confirmBoxX, y: confirmBoxY, w: INV_GRID.cellW, h: INV_GRID.cellH},
            changeTol: CHANGE_TOL, targetSamples: TARGET_SAMPLES,
            confirmTimeoutMs: CONFIRM_TIMEOUT_MS, pollMs: POLL_MS,
            label: "micro22"
        })
    } catch BotStopped {
        Say("micro22: STOPPED by F6 after " (A_TickCount - t0) " ms")
        return
    }
    elapsedMs := A_TickCount - t0

    msg := result
        ? "CONFIRMED - pickup registered (" elapsedMs " ms)"
        : "NOT CONFIRMED - image never appeared, or pickup never registered (" elapsedMs " ms)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=wait+click+confirm pickup  F6=request stop  Esc=exit."
    . " Image=" IMAGE_PATH " confirmSlot=" CONFIRM_SLOT)
ToolTip("micro 22 ready - F5 to run", 20, 20)
