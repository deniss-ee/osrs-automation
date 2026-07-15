; ============================================================
; SlotSignature.ahk
; Snapshots every pixel in a small fixed box and later checks
; whether any of them changed - used to confirm an item pickup
; actually landed (a specific inventory-slot sub-region visibly
; changes), independent of full/empty inventory gating.
; ============================================================

#Requires AutoHotkey v2.0

#Include ..\Detection\ColorSearch.ahk

class SlotSignature {
    ; x, y: top-left corner of the box to watch. w, h: box size.
    __New(x, y, w, h) {
        this._x := x
        this._y := y
        this._w := w
        this._h := h
    }

    ; Snapshots every pixel in the box (small box, cheap enough to sample
    ; exhaustively rather than sparsely).
    Snapshot() {
        sig := []
        loop this._h {
            row := A_Index - 1
            loop this._w {
                col := A_Index - 1
                sig.Push(PixelGetColor(this._x + col, this._y + row, "RGB"))
            }
        }
        return sig
    }

    ; True if any pixel in the box now differs from a prior Snapshot().
    HasChanged(previousSig, tol := 10) {
        idx := 1
        loop this._h {
            row := A_Index - 1
            loop this._w {
                col := A_Index - 1
                current := PixelGetColor(this._x + col, this._y + row, "RGB")
                if (!ColorSearch.ColorClose(current, previousSig[idx], tol))
                    return true
                idx += 1
            }
        }
        return false
    }
}
