; ============================================================
; v6 micro 03 - dynamic search area
;
; Proves a bot can widen its own search area at runtime when the
; target isn't where expected - the pattern v5 Agility uses after a
; Mark-of-Grace detour (dynamicSearchActive): try a small region first
; (fast, cheap), then a bigger one, then the whole screen, only as
; needed.
;
; WHAT IT DOES
;   F5  = try SMALL region -> if not found, try EXPANDED region -> if
;         not found, try WHOLE SCREEN. Tooltip reports which stage
;         found it (or that all three missed). No click.
;   F6  = clear the tooltip
;   Esc = exit the script
;
; Detection lives in Lib\Find.ahk (FindFilledBlock) - promoted here
; after in-game confirmation during Stage 1.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "03-dynamic-region"

; ======= EDIT THESE FOR YOUR TEST =======================================
TARGET_COLOR := 0xFF00FF   ; the RuneLite marker color to search for
COLOR_TOL := 5          ; per-channel tolerance (0-255)
BLOCK_W := 21         ; required solid block width in px
BLOCK_H := 21         ; required solid block height in px

; Stage 1: small region - where the target normally is.
SMALL_X1 := 734, SMALL_Y1 := 511, SMALL_X2 := 894, SMALL_Y2 := 600

; Stage 2: expanded region - wider net if stage 1 misses.
EXPANDED_X1 := 400, EXPANDED_Y1 := 300, EXPANDED_X2 := 1400, EXPANDED_Y2 := 900

; Stage 3: whole screen - last resort.
; (computed from A_ScreenWidth/Height at search time)
; ========================================================================

F5:: RunSearch()
F6:: {
    ToolTip()
    LogLine("F6 pressed - tooltip cleared")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunSearch() {
    t0 := A_TickCount

    tStage := A_TickCount
    LogLine("Stage 1 (small): region=" SMALL_X1 "," SMALL_Y1 " -> " SMALL_X2 "," SMALL_Y2)
    if (FindFilledBlock(SMALL_X1, SMALL_Y1, SMALL_X2, SMALL_Y2, TARGET_COLOR, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy)) {
        Report("SMALL", cx, cy, A_TickCount - t0)
        return
    }
    LogLine("Stage 1 (small): not found (searched " (A_TickCount - tStage) " ms)")

    tStage := A_TickCount
    LogLine("Stage 2 (expanded): region=" EXPANDED_X1 "," EXPANDED_Y1 " -> " EXPANDED_X2 "," EXPANDED_Y2)
    if (FindFilledBlock(EXPANDED_X1, EXPANDED_Y1, EXPANDED_X2, EXPANDED_Y2, TARGET_COLOR, COLOR_TOL,
        BLOCK_W, BLOCK_H, &cx, &cy)) {
        Report("EXPANDED", cx, cy, A_TickCount - t0)
        return
    }
    LogLine("Stage 2 (expanded): not found (searched " (A_TickCount - tStage) " ms)")

    x2 := A_ScreenWidth - 1
    y2 := A_ScreenHeight - 1
    tStage := A_TickCount
    LogLine("Stage 3 (whole screen): region=0,0 -> " x2 "," y2)
    if (FindFilledBlock(0, 0, x2, y2, TARGET_COLOR, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy)) {
        Report("WHOLE SCREEN", cx, cy, A_TickCount - t0)
        return
    }
    LogLine("Stage 3 (whole screen): not found (searched " (A_TickCount - tStage) " ms)")

    ; "ms total" (not "in N ms"/"(searched N ms)" like the other micros)
    ; is deliberate here, not a drift - this elapsed figure is cumulative
    ; across all 3 stages, not one search call, so it needs its own
    ; wording to avoid implying it's a single search's duration.
    elapsedMs := A_TickCount - t0
    msg := "NOT FOUND at any stage (" elapsedMs " ms total)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

; elapsedMs here is cumulative from RunSearch's t0 across every stage
; tried so far, not just the one that matched - "ms total" reflects that
; (matches the "not found" messages above, kept deliberately distinct
; from the single-search "in N ms" wording used elsewhere).
Report(stage, cx, cy, elapsedMs) {
    MouseMove(cx, cy, 5)
    msg := "FOUND via " stage " at " cx "," cy " (" elapsedMs " ms total)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=search (small->expanded->whole)  F6=clear tooltip  Esc=exit. Target=" HexColor(TARGET_COLOR))
ToolTip("micro 03 ready - F5 to search", 20, 20)
