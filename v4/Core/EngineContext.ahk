; ============================================================
; EngineContext.ahk
; The one state bag every Phase receives. Replaces legacy's
; global ctx[]/runner Map with a single explicit instance that
; is constructed once per bot and passed by reference into
; every Phase.Run(ctx) call - nothing in v4 reads state from
; anywhere else.
; ============================================================

#Requires AutoHotkey v2.0

class EngineContext {
    __New(config, logger, clicker, failsafe, waiter) {
        this.config := config
        this.logger := logger
        this.clicker := clicker
        this.failsafe := failsafe
        this.waiter := waiter
        this.timing := config.timing
        this.inventory := ""   ; set by bot entry point after construction
        this.bank := ""        ; set by bot entry point after construction
        this._state := Map()   ; free-form per-bot scratch state (e.g. locked target coords)
    }

    ; Scratch state accessors for values that don't warrant their own class
    ; (e.g. a locked color's last-seen coordinates). Prefer a real property
    ; on a dedicated class over this when the value has behavior, not just data.
    Get(key, default := "") => this._state.Has(key) ? this._state[key] : default

    Set(key, value) {
        this._state[key] := value
    }
}
