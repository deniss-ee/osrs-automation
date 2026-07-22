; ============================================================
; v7 micro 11 - find-and-click (M7 full: wait for a marker, click it)
;
; Port of v6's FindAndClickBlock shape (promoted in v6 from real bot
; call sites, never had its own dedicated micro) - but with two v7
; contract changes: clickOffsetX/Y are GONE entirely (no click-offset
; compensation anywhere in v7 - see Lib\Steps.ahk's header), and
; colors is an array (the v7 standard).
;
; SCOPED TO COLOR ONLY (image sibling dropped - see below): this
; composite covers the "same box gets clicked" case - a colored box
; appears, and something is now IN that spot, so click it. The other
; case ("different box, pure marker/gate - confirm A, then act on B,
; specifically to avoid a guessed fixed wait") is a DIFFERENT shape,
; planned for micro 18 (M9's two-stage marker->action), not this one.
; FindAndClickImage was cut from this micro entirely - it doesn't map
; to either real scenario this project actually needs right now, it
; was only included as FindAndClickBlock's PNG-flavored sibling.
;
; Reuses micro 06's EXACT convention: the block is a specific size at
; a specific known corner (MARKER_X/MARKER_Y + BLOCK_W/BLOCK_H), with
; MARGIN_PX as small search slack around that exact expected position -
; NOT a separate, arbitrarily-sized "search area" (that's a different
; concept, used in micro 04 for a genuinely looser/unknown position).
; This is the actual point of FindAndClickBlock: wait for a specific
; block at a specific expected spot, then act - not scan a broad
; region for it.
;
; F8 proves the clickX/clickY PIN (a legitimate override, distinct from
; the removed offset hack) by clicking a deliberately different point
; than the block's own found center, so you can see the pin actually
; wins.
;
; WHAT IT DOES
;   F5  = FindAndClickBlock: wait for the block (TARGET_COLORS) inside
;         the box built from MARKER_X/Y + BLOCK_W/H + MARGIN_PX, click
;         its found center. Reports found+clicked or timeout.
;   F8  = FindAndClickBlock again, but with clickX/clickY PINNED to
;         PIN_X,PIN_Y (deliberately offset from the block's own center)
;         - confirms the click lands at the PIN, not the found center.
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   Esc = exit the script (safe here - this composite doesn't send a
;         real Esc internally, unlike micros 09/10)
;
; LIVE CONFIRM:
;   1. Start F5 BEFORE the block is visible, then make it appear
;      partway through WAIT_TIMEOUT_MS - confirm the poll loop catches
;      it mid-wait (not just a same-instant check like micro 07's).
;   2. F5 with the block staying absent the whole time - confirm it
;      reports "never appeared" after WAIT_TIMEOUT_MS, no click fires.
;   3. F8 with the block present - confirm the click lands at PIN_X,
;      PIN_Y (visibly NOT the block's own center), proving the pin
;      overrides the found position rather than offsetting it.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "11-find-and-click"

; ======= EDIT THESE FOR YOUR TEST =======================================
; Same block color/size as micro 06.
TARGET_COLORS := [0xCC5D02]
COLOR_TOL := 5
BLOCK_W := 17
BLOCK_H := 17

; Corner-measured marker position (top-left corner) - the ONE position
; input, same convention as every other micro. MARGIN_PX is small
; search slack around this exact expected position, not a separate
; area size.
MARKER_X := 1630
MARKER_Y := 884
MARGIN_PX := 16

WAIT_TIMEOUT_MS := 30000   ; how long F5/F8 wait before reporting NOT FOUND

; A deliberately different point from the block's own center, to prove
; F8's clickX/clickY pin actually overrides the found position.
PIN_X := 1100
PIN_Y := 848
; ========================================================================

searchRegion := RegionAround(MARKER_X, MARKER_Y, BLOCK_W, BLOCK_H, MARGIN_PX)

F5:: RunFindAndClickBlock()
F8:: RunFindAndClickBlockPinned()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunFindAndClickBlock() {
    global g_StopRequested, searchRegion
    g_StopRequested := false

    LogLine("FindAndClickBlock started: colors=" JoinMsg(TARGET_COLORS, "/", HexColor))
    t0 := A_TickCount

    found := FindAndClickBlock({
        colors: TARGET_COLORS, tol: COLOR_TOL, blockW: BLOCK_W, blockH: BLOCK_H,
        region: searchRegion, waitTimeoutMs: WAIT_TIMEOUT_MS, label: "F5", itemLabel: "test block"
    })

    elapsedMs := A_TickCount - t0
    msg := found ? "FOUND and clicked block (" elapsedMs " ms)" : "NOT FOUND - block never appeared (" elapsedMs " ms)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

RunFindAndClickBlockPinned() {
    global g_StopRequested, searchRegion
    g_StopRequested := false

    LogLine("FindAndClickBlock (PINNED) started: colors=" JoinMsg(TARGET_COLORS, "/", HexColor)
        . " pin=" PIN_X "," PIN_Y)
    t0 := A_TickCount

    found := FindAndClickBlock({
        colors: TARGET_COLORS, tol: COLOR_TOL, blockW: BLOCK_W, blockH: BLOCK_H,
        region: searchRegion, clickX: PIN_X, clickY: PIN_Y,
        waitTimeoutMs: WAIT_TIMEOUT_MS, label: "F8", itemLabel: "test block"
    })

    elapsedMs := A_TickCount - t0
    msg := found
        ? "FOUND block, but clicked PIN at " PIN_X "," PIN_Y " instead (" elapsedMs " ms)"
        : "NOT FOUND - block never appeared, pin never used (" elapsedMs " ms)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=find+click block  F8=find block+click PIN  F6=request stop  Esc=exit.")
ToolTip("micro 11 ready - F5/F8 to test", 20, 20)
