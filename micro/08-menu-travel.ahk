; ============================================================
; v8 micro 08 - Steps.ahk pt 2: RightClickMenuItem,
; ClickUntilCondition, TravelToPoint
;
; Combines v7 micros 10 (right-click context menu), 20
; (click-until-condition retry cadence), and 23 (travel-to-point
; pin+search modes) into one micro.
;
; WHAT IT DOES
;   F5  = RightClickMenuItem: right-click MENU_TARGET, wait for
;         MENU_ITEM (image spec) in the popped-up menu, click it
;   F6  = request stop
;   F7  = ClickUntilCondition: click CLICK_TARGET once, wait
;         patiently, re-click on a cadence until WATCH_SLOT fills or
;         total timeout - simulates a laggy/contested target
;   F8  = probe: TravelToPoint PIN mode - click TRAVEL_PIN (a real
;         ClickTarget with its own size, not a bare point), wait for
;         ARRIVE_TARGET within tolerance of ARRIVE_AT
;   F9  = TravelToPoint SEARCH mode - same arrival check, but the
;         marker itself is found via TRAVEL_MARKER instead of pinned
;   F12 = exit
;
; LIVE CONFIRM:
;   1. F5 - menu opens, correct item clicked; on a miss, Esc closes
;      whatever did open rather than leaving a menu hanging.
;   2. F7 - first click, patient wait, then visible re-clicks on
;      RECLICK_MS cadence until the watched slot fills; confirm it
;      does NOT re-click during the patient first-wait window.
;   3. F8/F9 - both report arrival cleanly on success; on a
;      deliberately wrong ARRIVE_AT, confirm the diagnostic reports
;      whether the arrive-target was found elsewhere or nowhere.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v8.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "08-menu-travel"

; ======= EDIT THESE FOR YOUR TEST =======================================
MENU_TARGET := ClickTarget(1249, 712, 45, 45)
; transColor 0x5D5447 wildcards the menu's translucent background (65.6%
; of the image per histogram) - OSRS context menus blend with whatever
; 3D scene is behind them, so an exact-rectangle match without this
; wildcard can never survive a different background scene. Only the
; actual text pixels (cyan/white/black) need to match now.
MENU_ITEM := {path: IMAGES_DIR "\li_bank-deposit-box.png", w: 332, h: 30, tol: 15, transColor: "0x5D5447"}
MENU_WAIT_TIMEOUT_MS := 5000

CLICK_TARGET := ClickTarget(1249, 712, 45, 45)
WATCH_SLOT_X := 2099
WATCH_SLOT_Y := 801
WATCH_SLOT_COLORS := [0x3F3629]
WATCH_SLOT_TOL := 5
FIRST_WAIT_MS := 3000
RECLICK_MS := 2000
TOTAL_TIMEOUT_MS := 20000

TRAVEL_PIN := ClickTarget(1249, 712, 13, 13)
TRAVEL_MARKER := {colors: [0xFF980A], tol: 5, w: 13, h: 13}
TRAVEL_MARKER_REGION := GameZoneRegion()
TRAVEL_MARKER_WAIT_TIMEOUT_MS := 10000
ARRIVE_TARGET := {colors: [0x00FF00], tol: 5, w: 20, h: 20}
ARRIVE_AT := {x: 1249, y: 712}
ARRIVE_POS_TOL_PX := 20
ARRIVE_WAIT_TIMEOUT_MS := 10000
; ==========================================================================

RunMenuClick() {
    return RightClickMenuItem({
        at: MENU_TARGET, menuItem: MENU_ITEM, waitTimeoutMs: MENU_WAIT_TIMEOUT_MS, label: "micro08-menu"
    })
}

RunClickUntil() {
    ; the click closure must return a bool - ClickUntilCondition aborts
    ; if click() reports failure, and ClickAt itself returns nothing
    return ClickUntilCondition({
        click: () => (ClickAt(CLICK_TARGET), true),
        condition: () => !IsAnyColorAt(WATCH_SLOT_X, WATCH_SLOT_Y, WATCH_SLOT_COLORS, WATCH_SLOT_TOL, &fc),
        firstWaitMs: FIRST_WAIT_MS, reclickMs: RECLICK_MS, totalTimeoutMs: TOTAL_TIMEOUT_MS,
        label: "micro08-click-until", itemLabel: "watch slot filled"
    })
}

ProbeTravelPin() {
    return TravelToPoint({
        markerClick: TRAVEL_PIN, arrive: ARRIVE_TARGET, arriveAt: ARRIVE_AT,
        arrivePosTolPx: ARRIVE_POS_TOL_PX, arriveWaitTimeoutMs: ARRIVE_WAIT_TIMEOUT_MS,
        label: "micro08-travel-pin"
    })
}

RunTravelSearch() {
    return TravelToPoint({
        marker: TRAVEL_MARKER, markerRegion: TRAVEL_MARKER_REGION, markerWaitTimeoutMs: TRAVEL_MARKER_WAIT_TIMEOUT_MS,
        arrive: ARRIVE_TARGET, arriveAt: ARRIVE_AT,
        arrivePosTolPx: ARRIVE_POS_TOL_PX, arriveWaitTimeoutMs: ARRIVE_WAIT_TIMEOUT_MS,
        label: "micro08-travel-search"
    })
}

InstallBotHarness({
    run: RunMenuClick,
    label: "micro08",
    probe: ProbeTravelPin,
    extraHotkeys: [
        {key: "F7", handler: RunClickUntil, label: "click-until-condition"},
        {key: "F9", handler: RunTravelSearch, label: "travel-search"}
    ]
})
