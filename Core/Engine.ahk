; ============================================================
; Engine.ahk
; Owns the phase graph and the tick loop - busy-guard, per-phase
; timeout via FailSafe, "same name returned = stay" contract.
; ============================================================

#Requires AutoHotkey v2.0

#Include Phase.ahk
#Include FailSafe.ahk

class Engine {
    __New(ctx, intervalMs := 150) {
        this.ctx := ctx
        this._intervalMs := intervalMs
        this._phases := Map()       ; name -> Phase instance
        this._timeouts := Map()     ; name -> timeoutMs
        this.running := false
        this._busy := false
        this.currentPhase := ""
        this._tickFn := () => this.Tick()
    }

    ; Registers a Phase under its own .name. timeoutMs=0 means unlimited.
    AddPhase(phase, timeoutMs := 0) {
        this._phases[phase.name] := phase
        this._timeouts[phase.name] := timeoutMs
    }

    Start(startPhaseName) {
        this.running := true
        this._busy := false
        this.currentPhase := startPhaseName
        this.ctx.failsafe.EnterPhase(startPhaseName, this._timeouts.Get(startPhaseName, 0))
        SetTimer(this._tickFn, this._intervalMs)
        this.ctx.logger.Log("Engine: started at phase '" startPhaseName "'")
    }

    Stop(reason := "Stopped") {
        this.running := false
        SetTimer(this._tickFn, 0)
        this.ctx.logger.Log("Engine: stopped - " reason)
    }

    ; Force-jump to a phase regardless of current state (manual recovery).
    JumpToPhase(phaseName) {
        this.currentPhase := phaseName
        this.ctx.failsafe.EnterPhase(phaseName, this._timeouts.Get(phaseName, 0))
        this.ctx.logger.Log("Engine: manual jump to phase '" phaseName "'")
    }

    ; The timer callback. Safe to call manually for single-step debugging.
    Tick() {
        if (!this.running || this._busy)
            return

        if (this.ctx.failsafe.HasPhaseTimedOut()) {
            this.Stop("Phase '" this.currentPhase "' timed out")
            return
        }

        if (!this._phases.Has(this.currentPhase)) {
            this.Stop("Unknown phase '" this.currentPhase "'")
            return
        }

        this._busy := true
        try {
            nextPhaseName := this._phases[this.currentPhase].Run(this.ctx)
        } finally {
            this._busy := false
        }

        if (nextPhaseName != this.currentPhase) {
            this.currentPhase := nextPhaseName
            this.ctx.failsafe.EnterPhase(nextPhaseName, this._timeouts.Get(nextPhaseName, 0))
        }
    }
}
