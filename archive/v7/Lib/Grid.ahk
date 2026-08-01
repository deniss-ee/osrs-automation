; ============================================================
; v7 Lib\Grid.ahk - generalized grid addressing
;
; One set of functions parameterized by a GridSpec object - subsumes
; v6's SlotCorner/SlotCenter/BankSlotCenter and sudoku's local
; MenuItemCorner (all the same col/row/gap math with different
; constants). Any regular row-major grid reuses this.
; ============================================================

GridSpec(originX, originY, cols, rows, cellW, cellH, gapX := 0, gapY := 0) {
    return {originX: originX, originY: originY, cols: cols, rows: rows,
        cellW: cellW, cellH: cellH, gapX: gapX, gapY: gapY}
}

; 1-based row-major index -> the cell's top-left CORNER.
GridCorner(grid, index, &x, &y) {
    total := grid.cols * grid.rows
    if (index < 1 || index > total)
        throw ValueError("GridCorner: index " index " out of range (1.." total ")")

    col := Mod(index - 1, grid.cols)
    row := (index - 1) // grid.cols

    x := grid.originX + col * (grid.cellW + grid.gapX)
    y := grid.originY + row * (grid.cellH + grid.gapY)
}

; Same indexing, cell CENTER (derived via CenterX/CenterY, standard #2).
GridCenter(grid, index, &x, &y) {
    GridCorner(grid, index, &cx, &cy)
    x := CenterX(cx, grid.cellW)
    y := CenterY(cy, grid.cellH)
}

; The cell's box as [x1,y1,x2,y2] - for in-cell classification.
GridCellRegion(grid, index) {
    GridCorner(grid, index, &x, &y)
    return [x, y, x + grid.cellW, y + grid.cellH]
}
