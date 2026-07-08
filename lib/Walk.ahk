; ============================================================
; Walk.ahk - NEW
;
; Auto-walk-with-waiting: click a destination marker, then block
; until an arrival signal appears (a different color/image, or
; the destination marker itself disappears). Replaces flat-seconds
; sleeps (motherlode's "guess 10 seconds") with real signal-based waiting.
;
; Depends on: Colors.ahk (WaitForPixelSearch, WaitForPixelColor, WaitForPixelColorChange), Images.ahk (WaitForImageCenter, WaitUntilImageGone), Click.ahk (HumanClick), TaskRunner.ahk (ResetPhaseTimer), Context.ahk
; ============================================================

#Requires AutoHotkey v2.0

#Include Colors.ahk
#Include Images.ahk
#Include Click.ahk
#Include TaskRunner.ahk
#Include Context.ahk
#Include Targeting.ahk

; Walks to a destination by clicking a marker, then blocks until an
; arrival signal confirms the walk completed. The arrival signal can be:
; - A pixel appearing (mode: "appear")
; - A pixel disappearing (mode: "disappear")
; - An image appearing (mode: "appear")
; - An image disappearing (mode: "disappear")
;
; destMarker: {color, tolerance, x1, y1, x2, y2, clickOffsetX, clickOffsetY}
; arrival: one of:
;   {mode: "appear", color, tolerance, x, y}
;   {mode: "appear", file, w, h, x1, y1, x2, y2, options}
;   {mode: "disappear", color, tolerance, x, y}
;   {mode: "disappear", file, w, h, x1, y1, x2, y2, options}
;
; centroid: false (default) finds the first matching pixel (fast, fine for
; small/precise markers). true finds the CENTER of the whole colored blob
; instead (FindOutlineBlobCenter) - use this for a painted ground-tile
; marker covering an area, where clicking dead-center is more reliable
; than whichever edge pixel a raw scan hits first.
;
; Returns true once arrival confirmed, false if marker not found or arrival timeout.
WalkToMarker(ctx, destMarker, markerTimeoutMs, arrival, arrivalTimeoutMs, confirmTicks := 3, centroid := false, sampleRate := 2) {
    if (centroid) {
        if (!WaitForBlobCenter(ctx, &fx, &fy, destMarker["x1"], destMarker["y1"], destMarker["x2"], destMarker["y2"], destMarker["color"], destMarker["tolerance"], markerTimeoutMs, sampleRate))
            return false
    } else if (!WaitForPixelSearch(ctx, &fx, &fy, destMarker["x1"], destMarker["y1"], destMarker["x2"], destMarker["y2"], destMarker["color"], destMarker["tolerance"], markerTimeoutMs)) {
        return false
    }

    HumanClick(fx + destMarker["clickOffsetX"], fy + destMarker["clickOffsetY"], 0, 0, ctx["runMode"])
    ResetPhaseTimer(ctx["runner"])

    ; Determine what "arrival" means and wait for it
    arrived := false
    if (arrival["mode"] = "appear") {
        if (arrival.Has("file")) {
            ; Image appearance
            arrived := WaitForImageCenter(ctx, arrival["x1"], arrival["y1"], arrival["x2"], arrival["y2"], arrival["file"], arrival["w"], arrival["h"], &acx, &acy, arrivalTimeoutMs, arrival.Has("options") ? arrival["options"] : "")
        } else {
            ; Pixel appearance
            arrived := WaitForPixelColor(ctx, arrival["x"], arrival["y"], arrival["color"], arrival["tolerance"], arrivalTimeoutMs, confirmTicks)
        }
    } else if (arrival["mode"] = "disappear") {
        if (arrival.Has("file")) {
            ; Image disappearance
            arrived := WaitUntilImageGone(ctx, arrival["x1"], arrival["y1"], arrival["x2"], arrival["y2"], arrival["file"], arrivalTimeoutMs, confirmTicks, arrival.Has("options") ? arrival["options"] : "")
        } else {
            ; Pixel disappearance
            arrived := WaitForPixelColorChange(ctx, arrival["x"], arrival["y"], arrival["color"], arrival["tolerance"], arrivalTimeoutMs, confirmTicks)
        }
    }

    if (arrived)
        ResetPhaseTimer(ctx["runner"])

    return arrived
}
