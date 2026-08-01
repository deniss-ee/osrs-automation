; ============================================================
; v6 micro 11 - pickup-appeared (the Mark of Grace pattern)
;
; The first-class building block: "find something that just appeared
; -> click it -> confirm the pickup actually landed via a pixel-box
; diff" - not just "did we click", but "did the game state actually
; change afterward".
;
; ORDER MATTERS: snapshot the confirm box BEFORE clicking, not after -
; you need the "before" state to detect a change caused by the click.
;
; WHAT IT DOES
;   F5  = wait for the image to appear (timeout) -> snapshot confirm
;         box -> click the found item -> wait for the box to change
;         (timeout) -> report which of the 4 outcomes happened:
;         confirmed / clicked-but-not-confirmed / never-appeared / stopped
;   F7  = trace the confirm box's outline (same as micro 10) - use
;         this first to double check the box still lines up
;   F6  = request stop (interrupts EITHER wait)
;   Esc = exit the script
;
; This composite now lives in Lib\Steps.ahk as PickupAppeared(opts) -
; this file just builds the opts from calibration constants and calls
; it, so this test also re-confirms the promoted Lib version behaves
; identically to the original inline flow.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "11-pickup-appeared"

; ======= EDIT THESE FOR YOUR TEST =======================================
IMAGE_PATH := A_ScriptDir "\..\img\air-rune.png"
IMAGE_W    := 78   ; measured from the PNG's own IHDR
IMAGE_H    := 16
IMAGE_TOL  := 5
TRANS_COLOR := "0x00FF00"   ; background color to treat as see-through ("" to disable)

REGION_X1 := 0, REGION_Y1 := 0, REGION_X2 := A_ScreenWidth - 1, REGION_Y2 := A_ScreenHeight - 1
APPEAR_TIMEOUT_MS := 15000   ; give up if the item never appears

CLICK_OFFSET_X := 0   ; offset from the found image's CENTER to the actual
CLICK_OFFSET_Y := 4   ; click point (tune if the image anchor's center isn't
                       ; quite the clickable spot)
CLICK_USE_CTRL := true

; Confirm box - ALWAYS BOX_W x BOX_H, offset by BOX_OFFSET_X/Y from a
; corner. Set SLOT_INDEX to offset from a DIFFERENT slot's corner
; instead of slot 1's - leave it "" to use slot 1's own corner (default:
; the 52x16 counter area at offset 2,0). SLOT_INDEX never changes the
; box's SIZE, only which slot's corner it's offset from.
SLOT_INDEX := "2"
BOX_OFFSET_X := 2, BOX_OFFSET_Y := 0
BOX_W := 52, BOX_H := 16
CHANGE_TOL := 10

; Sample budget, NOT a fixed stride - see Lib\Inv.ahk's TakeSnapshot.
TARGET_SAMPLES := 50

CONFIRM_TIMEOUT_MS := 8000   ; give up waiting for the pickup to register
POLL_MS   := 300             ; tick-aligned poll interval (both waits)
; ========================================================================

; Resolve the confirm box's base corner (same pattern as micro 10): a
; specific slot's corner via SlotCorner, or slot 1's own corner when
; SLOT_INDEX is "" - then offset BOX_OFFSET_X/Y from it. BOX_W/BOX_H
; are never touched here; they stay exactly what's configured above.
if (SLOT_INDEX != "")
    SlotCorner(SLOT_INDEX, &baseX, &baseY)
else {
    baseX := INV_FIRST_X
    baseY := INV_FIRST_Y
}
BOX_X := baseX + BOX_OFFSET_X
BOX_Y := baseY + BOX_OFFSET_Y

F5:: RunPickup()
F7:: TraceBoxOutline()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

TraceBoxOutline() {
    corners := [
        [BOX_X, BOX_Y], [BOX_X + BOX_W, BOX_Y],
        [BOX_X + BOX_W, BOX_Y + BOX_H], [BOX_X, BOX_Y + BOX_H], [BOX_X, BOX_Y]
    ]
    LogLine("F7: tracing confirm box outline " BOX_X "," BOX_Y " " BOX_W "x" BOX_H)
    ToolTip("Tracing confirm box outline...", 20, 20)
    for c in corners {
        MouseMove(c[1], c[2], 20)
        Sleep(400)
    }
}

RunPickup() {
    global g_StopRequested
    g_StopRequested := false

    opts := {
        imagePath: IMAGE_PATH, imageW: IMAGE_W, imageH: IMAGE_H, imageTol: IMAGE_TOL, transColor: TRANS_COLOR,
        region: [REGION_X1, REGION_Y1, REGION_X2, REGION_Y2], appearTimeoutMs: APPEAR_TIMEOUT_MS,
        clickOffsetX: CLICK_OFFSET_X, clickOffsetY: CLICK_OFFSET_Y, ctrl: CLICK_USE_CTRL,
        confirmBox: {x: BOX_X, y: BOX_Y, w: BOX_W, h: BOX_H},
        changeTol: CHANGE_TOL, targetSamples: TARGET_SAMPLES,
        confirmTimeoutMs: CONFIRM_TIMEOUT_MS, pollMs: POLL_MS
    }

    LogLine("Pickup flow started (via Lib\Steps.ahk PickupAppeared): image=" IMAGE_PATH
        . " appearTimeout=" APPEAR_TIMEOUT_MS "ms confirmBox=" BOX_X "," BOX_Y " " BOX_W "x" BOX_H
        . " confirmTimeout=" CONFIRM_TIMEOUT_MS "ms")
    ToolTip("Waiting for item to appear (F6 to cancel)...", 20, 20)

    try {
        PickupAppeared(opts)
    } catch BotStopped as e {
        msg := "STOPPED by F6"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }
    ; PickupAppeared already Say()'d the detailed outcome (confirmed /
    ; never-appeared / clicked-not-confirmed) - nothing more to report.
}

LogLine("Script loaded. F5=run pickup flow  F7=trace confirm box  F6=stop  Esc=exit")
ToolTip("micro 11 ready - F7 to check confirm box, F5 to run the pickup flow", 20, 20)
