; ============================================================
; Context.ahk
;
; Bot context object - replaces heavy per-function global X,Y,Z boilerplate.
; One mutable Map every phase function receives, built once at script startup
; from the loaded config; phases read/write through this object only.
;
; v3 convention: every phase function takes (ctx, runner) instead of declaring
; a dozen `global X, Y, Z` lines. All bot-specific configuration (tunables,
; elements, markers, images, calibrated regions/points/paths) is accessed
; through ctx, not via global variables.
; ============================================================

#Requires AutoHotkey v2.0

; ============================================================
; NewBotContext - create the root context object
; ============================================================
; configFile: path to the bot's .ini file
; returns: Map with all the nested config Maps and state fields
NewBotContext(configFile) {
    return Map(
        "config", configFile,           ; path to the bot's .ini
        "tunables", Map(),              ; flat key->value, e.g., colorTolerance, smeltTimeoutMs
        "elements", Map(),              ; name -> {x, y, w, h} UI regions (inventory slots, buttons, etc.)
        "markers", Map(),               ; name -> {color, tolerance, x1, y1, x2, y2, clickOffsetX, clickOffsetY}
        "images", Map(),                ; name -> {file, w, h, options, x1, y1, x2, y2}
        "slotSignatures", Map(),        ; name -> {slot, points:[{x, y, color}]} - calibrated slot baselines
        "withdrawPlans", Map(),         ; name -> [{slot, count}, ...] - ordered bank withdrawal sequences
        "targetRegions", Map(),         ; name -> {color, tolerance, x1, y1, x2, y2} - for NPC/enemy targeting
        "paths", Map(),                 ; name -> steps array - recorded mouse-click walks
        "runner", "",                   ; TaskRunner object (set after NewTaskRunner; "" = not started)
        "logFile", "",                  ; debug log file path (set by script if logging enabled)
        "runMode", false,               ; run vs walk flag (read once at startup, affects HumanClick)
        "paused", false                 ; explicit pause state (set by Safety.ahk's UpdatePausedState)
    )
}

; ============================================================
; Context accessor convenience functions
; ============================================================
; These eliminate boilerplate at call sites - instead of
; ctx["tunables"].Has("x") ? ctx["tunables"]["x"] : default
; just: CtxTunable(ctx, "x", default)
;
; All accessors assume the key exists (or return the default for Ctx* that take one).
; If a key is missing, the caller's validation hotkey should have caught it.

; Get a tunable value with a default fallback
CtxTunable(ctx, key, default := 0) => ctx["tunables"].Has(key) ? ctx["tunables"][key] : default

; Get a named element (UI region)
CtxElement(ctx, name) => ctx["elements"][name]

; Get a named marker (color + search region)
CtxMarker(ctx, name) => ctx["markers"][name]

; Get a named image spec
CtxImage(ctx, name) => ctx["images"][name]

; Get a named slot signature (for Slots.ahk checks)
CtxSlotSignature(ctx, name) => ctx["slotSignatures"][name]

; Get a named withdraw plan
CtxWithdrawPlan(ctx, name) => ctx["withdrawPlans"][name]

; Get a named target region (for Targeting.ahk)
CtxTargetRegion(ctx, name) => ctx["targetRegions"][name]

; Get a named recorded path
CtxPath(ctx, name) => ctx["paths"][name]

; Centralized "should I still be going" check - true only if runner exists, is running, and not paused
CtxIsRunning(ctx) => ctx["runner"] != "" && ctx["runner"]["running"] && !ctx["paused"]
