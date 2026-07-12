; ============================================================
; EngineContext.ahk
; The one state bag every Phase receives, passed by reference
; into every Phase.Run(ctx) call.
; ============================================================

#Requires AutoHotkey v2.0

class EngineContext {
    __New(config, logger, clicker, failsafe, waiter, windowFocus := "", overlay := "") {
        this.config := config
        this.logger := logger
        this.clicker := clicker
        this.failsafe := failsafe
        this.waiter := waiter
        this.timing := config.timing
        this.windowFocus := windowFocus   ; a WindowFocus, or "" to opt out
        this.overlay := overlay           ; an Overlay, or "" to opt out
        this.inventory := ""   ; set by the bot entry point after construction
        this.bank := ""        ; set by the bot entry point after construction
        this.engine := ""      ; set after Engine construction, so a Phase can stop it
        this._state := Map()   ; free-form per-bot scratch state
    }

    ; Scratch state for values that don't warrant their own class.
    Get(key, default := "") => this._state.Has(key) ? this._state[key] : default

    Set(key, value) {
        this._state[key] := value
    }

    ; Fans a log line out to both the file logger and the overlay.
    Log(text) {
        this.logger.Log(text)
        if (this.overlay != "")
            this.overlay.Log(text)
    }
}
