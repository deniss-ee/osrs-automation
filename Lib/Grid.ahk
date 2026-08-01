; ============================================================
; v8 Lib\Grid.ahk - parameterized grid addressing (one grid math
; implementation for inventory, bank, or any other cell layout)
;
; Ported verbatim from v7\Lib\Grid.ahk except GridCellRegion, which
; had an off-by-one inconsistency in v7: Steps.ahk\VerifySlotsAndDrop
; hand-rolled the SAME box using an inclusive `cx + w - 1` bound
; while GridCellRegion itself used an exclusive `x + cellW` bound -
; two different definitions of "this cell's region" existing side by
; side. v8 fixes GridCellRegion to the inclusive form and makes it
; the ONLY definition - VerifySlotsAndDrop (Steps.ahk) calls it
; instead of re-deriving the box itself.
; ============================================================

GridSpec(originX, originY, cols, rows, cellW, cellH, gapX := 0, gapY := 0) {
    return {originX: originX, originY: originY, cols: cols, rows: rows,
        cellW: cellW, cellH: cellH, gapX: gapX, gapY: gapY}
}

GridCorner(grid, index, &x, &y) {
    if (index < 1 || index > grid.cols * grid.rows)
        throw ValueError("GridCorner: index " index " out of range for a " grid.cols "x" grid.rows " grid")
    col := Mod(index - 1, grid.cols)
    row := (index - 1) // grid.cols
    x := grid.originX + col * (grid.cellW + grid.gapX)
    y := grid.originY + row * (grid.cellH + grid.gapY)
}

GridCenter(grid, index, &x, &y) {
    GridCorner(grid, index, &cx, &cy)
    x := CenterX(cx, grid.cellW)
    y := CenterY(cy, grid.cellH)
}

; [x1, y1, x2, y2] region for one cell, inclusive bounds - the ONE
; definition of "this cell's box" (Steps.ahk\VerifySlotsAndDrop uses
; this instead of re-deriving it).
GridCellRegion(grid, index) {
    GridCorner(grid, index, &cx, &cy)
    return [cx, cy, cx + grid.cellW - 1, cy + grid.cellH - 1]
}
