---
name: feedback_walk_markers
description: Walk marker detection - use WaitForPixelSearch (first pixel), not blob centroid
metadata:
  type: feedback
---

Use `WaitForPixelSearch` to find the first matching pixel in a region, then click it directly with offset (0,0). Do NOT use `WalkToMarker` with `centroid:=true` (`WaitForBlobCenter`) for minimap/ground markers — it's unreliable and slower than a simple pixel scan.

**Why:** The centroid approach silently failed to find the marker; plain `WaitForPixelSearch` worked immediately.

**How to apply:** In any bot that clicks a colored minimap tile or ground marker: `WaitForPixelSearch` → `HumanClick(fx + offsetX, fy + offsetY)` → wait for arrival image. Keep offsets configurable in ini (default 0,0).
