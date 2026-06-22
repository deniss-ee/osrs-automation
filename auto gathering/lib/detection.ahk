; ============================================================
;  detection.ahk - "IS THE ROCK / TREE READY TO CLICK?"
; ------------------------------------------------------------
;  ELI5: The bot can't "see" the game like you do. All it can do
;  is ask Windows "what color is the pixel at this exact x,y spot
;  on screen?" via PixelGetColor. A full ore rock is a different
;  color than an empty/depleted one, so we remember the "full"
;  color when you calibrate (F1), then keep re-checking that same
;  pixel - if the color is close enough to what we remember, the
;  rock is ready.
; ============================================================

#Requires AutoHotkey v2.0

; --------------------------------------------------------------
; ColorClose: are two colors "basically the same"? We compare
; Red, Green and Blue separately instead of the whole number,
; because game lighting/shadows can shift colors slightly even
; when the rock is still "full" - a strict equality check would
; constantly false-negative on shimmer/lighting effects.
;
; A color number is one big integer like 0xRRGGBB. ">> 16" slides
; the bits right so Red ends up in the last 8 bits, then "& 0xFF"
; keeps only those last 8 bits (masks off everything else).
; --------------------------------------------------------------
ColorClose(c1, c2, tolerance) {
    r1 := (c1 >> 16) & 0xFF
    g1 := (c1 >> 8)  & 0xFF
    b1 := c1 & 0xFF

    r2 := (c2 >> 16) & 0xFF
    g2 := (c2 >> 8)  & 0xFF
    b2 := c2 & 0xFF

    return (Abs(r1 - r2) <= tolerance && Abs(g1 - g2) <= tolerance && Abs(b1 - b2) <= tolerance)
}

; --------------------------------------------------------------
; IsSpotReady: checks ONE gathering spot (a Map with x/y/color)
; against the live pixel on screen right now. tolerance comes
; from the caller so different profiles (sharper textures vs
; shimmery ones) can tune it without editing this file.
; --------------------------------------------------------------
IsSpotReady(spot, tolerance) {
    liveColor := PixelGetColor(spot["x"], spot["y"], "RGB")
    return ColorClose(liveColor, spot["color"], tolerance)
}

; --------------------------------------------------------------
; IsInventoryFull: same trick as ore detection, but inverted -
; we remember the color of an EMPTY inventory slot. If the live
; color is no longer close to that, something got placed there,
; meaning the inventory slot (and therefore probably the whole
; inventory, if you calibrated the last slot) is full.
; --------------------------------------------------------------
IsInventoryFull(tolerance := 10) {
    global State
    liveColor := PixelGetColor(State["invX"], State["invY"], "RGB")
    return !ColorClose(liveColor, State["invDefaultColor"], tolerance)
}
