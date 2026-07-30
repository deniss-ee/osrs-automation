; ============================================================
; v7 micro 16 - wait for a PNG marker to appear/disappear
; (WaitForImage/WaitForImageGone)
;
; New ground (M2 poll variant, no v6 precedent) - micro 07 proved a
; single one-shot FindImage check; this proves the same search polled
; over time via WaitUntil, the same "wait for a state" shape micro 15's
; WatchIndicator gave colors, applied to a PNG marker instead.
;
; Reuses the exact-box convention from micro 07: PNG markers sit at one
; fixed known screen position, so the search box is EXACT (marginPx=0
; via RegionAround), not padded like a roaming color target.
;
; WHAT IT DOES
;   F5  = WaitForImage: waits until IMAGE_PATH appears in the exact
;         MARKER box, or WAIT_TIMEOUT_MS elapses
;   F7  = WaitForImageGone: waits until IMAGE_PATH is NO LONGER visible
;         in the exact MARKER box, or WAIT_TIMEOUT_MS elapses
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   Esc = exit the script
;
; LIVE CONFIRM: same image/marker as micro 07 (deposit-motherlode.png
; at 80x72, MARKER_X/Y=775,765) for a direct apples-to-apples test
; against that micro's already-confirmed one-shot result. With it NOT
; visible, press F5, then make it appear before WAIT_TIMEOUT_MS -
; should report FOUND. With it visible, press F7, then make it
; disappear before timeout - should report GONE. Also confirm each
; hotkey times out cleanly if the state never changes, and F6
; interrupts mid-wait.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "16-wait-image"

; ======= EDIT THESE FOR YOUR TEST =======================================
; Same image + marker as micro 07, for direct comparison against its
; already-confirmed one-shot FindImage result.
IMAGE_PATH := A_ScriptDir "\..\Images\deposit-motherlode.png"
IMAGE_W := 80          ; must match the PNG's real pixel size
IMAGE_H := 72
IMAGE_TOL := 5          ; shade-of-variation tolerance, 0-255 (0 = exact)
TRANS_COLOR := "0x00FF00"   ; background color to treat as see-through ("" to disable)

; Corner-measured marker position (top-left corner) - same convention
; as micro 07. Exact box, no padding (PNG markers sit at one fixed
; known screen position, unlike a roaming color target).
MARKER_X := 775
MARKER_Y := 765
MARGIN_PX := 0

WAIT_TIMEOUT_MS := 15000
POLL_MS         := 100
; ========================================================================

; Derived exact search box - same RegionAround call micro 07 uses.
region := RegionAround(MARKER_X, MARKER_Y, IMAGE_W, IMAGE_H, MARGIN_PX)
REGION_X1 := region[1]
REGION_Y1 := region[2]
REGION_X2 := region[3]
REGION_Y2 := region[4]

F5:: RunWaitForImage()
F7:: RunWaitForImageGone()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunWaitForImage() {
    global g_StopRequested
    g_StopRequested := false

    LogLine("F5: waiting for image to appear - " IMAGE_PATH " in " REGION_X1 "," REGION_Y1 " -> " REGION_X2 "," REGION_Y2)
    ToolTip("Waiting for image to appear (F6 to cancel)...", 20, 20)

    t0 := A_TickCount
    try {
        found := WaitForImage(REGION_X1, REGION_Y1, REGION_X2, REGION_Y2, IMAGE_PATH, IMAGE_W, IMAGE_H, IMAGE_TOL, TRANS_COLOR, WAIT_TIMEOUT_MS, POLL_MS, &cx, &cy)
    } catch BotStopped {
        msg := "STOPPED by F6 after " (A_TickCount - t0) " ms waiting for image"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }
    elapsedMs := A_TickCount - t0

    if (found) {
        MouseMove(cx, cy, 5)
        msg := "FOUND at " cx "," cy " after " elapsedMs " ms"
    } else {
        msg := "TIMED OUT after " elapsedMs " ms - image never appeared"
    }
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

RunWaitForImageGone() {
    global g_StopRequested
    g_StopRequested := false

    LogLine("F7: waiting for image to disappear - " IMAGE_PATH)
    ToolTip("Waiting for image to disappear (F6 to cancel)...", 20, 20)

    t0 := A_TickCount
    try {
        gone := WaitForImageGone(REGION_X1, REGION_Y1, REGION_X2, REGION_Y2, IMAGE_PATH, IMAGE_W, IMAGE_H, IMAGE_TOL, TRANS_COLOR, WAIT_TIMEOUT_MS, POLL_MS)
    } catch BotStopped {
        msg := "STOPPED by F6 after " (A_TickCount - t0) " ms waiting for image to be gone"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }
    elapsedMs := A_TickCount - t0

    msg := gone ? "GONE after " elapsedMs " ms" : "TIMED OUT after " elapsedMs " ms - image never disappeared"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=wait for appear  F7=wait for gone  F6=request stop  Esc=exit."
    . " Image=" IMAGE_PATH " at " MARKER_X "," MARKER_Y)
ToolTip("micro 16 ready - F5=wait for appear  F7=wait for gone", 20, 20)
