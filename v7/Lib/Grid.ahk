; ============================================================
; v7 Lib\Grid.ahk - generalized grid addressing (micro 12)
;
; Subsumes v6's SlotCorner/SlotCenter/BankSlotCenter (Inv.ahk) AND
; sudoku.ahk's local MenuItemCorner - all three were the exact same
; col/row/gap math with different constants baked in. Here it's ONE
; set of functions parameterized by a GridSpec object, so any grid
; (inventory, bank, a menu, anything with a regular row-major layout)
; reuses the same math instead of re-deriving it per bot.
;
; GridSpec is a plain object (not a Map), same style as opts elsewhere
; in v7. gapX/gapY default to 0 for grids with no gap between cells.
; ============================================================

GridSpec(originX, originY, cols, rows, cellW, cellH, gapX := 0, gapY := 0) {
    return {originX: originX, originY: originY, cols: cols, rows: rows,
        cellW: cellW, cellH: cellH, gapX: gapX, gapY: gapY}
}

; 1-based, row-major index (1 = top-left, left-to-right then
; top-to-bottom) -> that cell's top-left CORNER only - no size output,
; same "corner never a size" discipline v6's SlotCorner fixed.
GridCorner(grid, index, &x, &y) {
    total := grid.cols * grid.rows
    if (index < 1 || index > total)
        throw ValueError("GridCorner: index " index " out of range (1.." total ")")

    col := Mod(index - 1, grid.cols)
    row := (index - 1) // grid.cols

    x := grid.originX + col * (grid.cellW + grid.gapX)
    y := grid.originY + row * (grid.cellH + grid.gapY)
}

; Same indexing, but the cell's CENTER (corner + CenterX/CenterY, never
; a hand-typed center).
GridCenter(grid, index, &x, &y) {
    GridCorner(grid, index, &cx, &cy)
    x := CenterX(cx, grid.cellW)
    y := CenterY(cy, grid.cellH)
}

; The cell's full corner+size box as a [x1,y1,x2,y2] region - for
; in-cell classification (e.g. "does THIS slot's box contain a specific
; item image"), same shape RegionAround/GameZoneRegion return.
GridCellRegion(grid, index) {
    GridCorner(grid, index, &x, &y)
    return [x, y, x + grid.cellW, y + grid.cellH]
}
