; ============================================================
; Walk.ahk
; Waypoint-list traversal. Generalizes legacy's returnMine1/
; returnMine2 pattern (hardcoded minimap clicks + an ad hoc
; integer sub-stage ctx["return2Stage"]) into one ordered list
; of waypoints, each with its own click point and arrival
; anchor - consumed by a single phase or split across as many
; registered phases as needed, without a hand-rolled stage int.
; ============================================================

#Requires AutoHotkey v2.0

class Waypoint {
    __New(clickX, clickY, arrivalAnchor) {
        this.clickX := clickX
        this.clickY := clickY
        this.arrivalAnchor := arrivalAnchor   ; a DynamicTarget or StaticAnchor
    }
}

class Walk {
    __New(waypoints, clicker) {
        this._waypoints := waypoints   ; array of Waypoint, in order
        this._clicker := clicker
        this._index := 0
    }

    Reset() {
        this._index := 0
    }

    IsComplete() => this._index >= this._waypoints.Length

    CurrentWaypoint() => this._waypoints[this._index + 1]

    ; Clicks the current waypoint's click point.
    ClickCurrent() {
        wp := this.CurrentWaypoint()
        this._clicker.Click(wp.clickX, wp.clickY)
    }

    ; Checks the current waypoint's arrival anchor; advances to the next
    ; waypoint if arrived. Returns true once ALL waypoints are complete.
    CheckArrival(&x, &y) {
        wp := this.CurrentWaypoint()
        if (wp.arrivalAnchor.Find(&x, &y)) {
            this._index += 1
            return this.IsComplete()
        }
        return false
    }
}
