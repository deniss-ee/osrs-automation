; ============================================================
; MinePhase.ahk
; Placeholder phase proving the Engine/Phase/Timing/Detection/
; Action/Config wiring works end-to-end. Follows the mandatory
; 4-step shape (acquire -> wait -> act -> verify) from the v4
; ruleset. Real vein-finding logic is ported from
; auto-motherlode-v2.ahk's MinePhase (lines 128-238) in Phase 4/5 -
; this stub only proves the pipeline runs without erroring.
; ============================================================

#Requires AutoHotkey v2.0

#Include ..\..\Core\Phase.ahk

class MinePhase extends Phase {
    __New(vein) {
        super.__New("mine")
        this._vein := vein   ; a ColorBlockTarget
    }

    Run(ctx) {
        ; 1. ACQUIRE
        if (!this._vein.Find(&x, &y)) {
            ctx.logger.Log("MinePhase: no vein found yet")
            return "mine"
        }

        ; 2. WAIT
        ctx.waiter.After(ctx.timing, "mineClickCooldown")

        ; 3. ACT (stubbed - no real click yet, this is a no-op skeleton)
        ctx.logger.Log("MinePhase: would click vein at [" x ", " y "]")
        ctx.failsafe.ResetPhaseTimer(ctx)

        ; 4. VERIFY (stubbed - no real inventory gate wired yet)
        return "mine"
    }
}
