; ============================================================
;  detection.ahk - "IS THE ORE READY?" / "IS THE INVENTORY FULL?"
; ------------------------------------------------------------
;  ELI5: The bot can't "see" the game like you do - all it can
;  do is ask Windows "what color is the pixel at this exact x,y
;  spot on screen?" (PixelGetColor). A full ore rock is a
;  different color than a depleted one, so during setup (F1/F2)
;  we remember the "full" color at that pixel, then keep
;  re-checking it - if the live color is close enough to what we
;  remember, the rock is ready to click again.
; ============================================================

#Requires AutoHotkey v2.0

; --------------------------------------------------------------
; ColorClose: are two colors "basically the same"? We compare
; Red, Green, and Blue separately (instead of comparing the two
; numbers directly) because lighting/shadows in the game can
; shift colors slightly even when the rock is still "full" - a
; strict equality check would constantly false-negative on that
; shimmer.
;
; A color is one big number like 0xRRGGBB. ">> 16" slides the
; bits right so Red ends up in the last 8 bits, then "& 0xFF"
; keeps only those last 8 bits (throws away everything else).
; Same trick for Green (shift 8) and Blue (shift 0, i.e. no shift).
; --------------------------------------------------------------
ColorClose(c1, c2, tol) {
    r1 := (c1 >> 16) & 0xFF
    g1 := (c1 >> 8)  & 0xFF
    b1 := c1 & 0xFF

    r2 := (c2 >> 16) & 0xFF
    g2 := (c2 >> 8)  & 0xFF
    b2 := c2 & 0xFF

    return (Abs(r1 - r2) <= tol && Abs(g1 - g2) <= tol && Abs(b1 - b2) <= tol)
}

; --------------------------------------------------------------
; IsInventoryFull: same color-matching trick, but inverted - we
; remember the color of an EMPTY inventory slot during setup
; (F3). If the live color is no longer close to that remembered
; "empty" color, something must be sitting in that slot now,
; meaning the inventory is full.
; --------------------------------------------------------------
IsInventoryFull() {
    global invX, invY, invDefaultColor
    return PixelGetColor(invX, invY, "RGB") != invDefaultColor
}
