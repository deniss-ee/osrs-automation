---
name: reference_timing_tuning
description: Complete timing/delay tuning points for smelter bot
metadata:
  type: reference
---

## All Click & Delay Points in auto-smelter

### Hardcoded in Click.ahk (apply to all HumanClick calls):
- **Pre-click Ctrl hold:** 50ms (when holdCtrl=true)
- **Mouse move settle:** 150ms (always)
- **Post-click Ctrl release:** 50ms (when holdCtrl=true)
- **JitterDelay capping:** ±100ms max jitter (hardcoded global MAX_DELAY_JITTER_MS)

### Tunables in [Tunables] section of ini:
- `bankSettleMs=300` — pre-Deposit All pause
- `bankFailsafeMs=300` — post-Deposit All pause
- `withdrawInterSettleMs=600` — pause after EACH withdrawal click (except last)
- `withdrawFinalSettleMs=300` — pause after FINAL withdrawal click
- `spaceKeySettleMs=200` — pause after pressing Space in smelt dialog

### Apply JitterDelay to all of above — values in ini are base, actual = base ± up to 15% (capped at ±100ms)

When ENABLE_HUMANIZATION in Click.ahk is false, all JitterDelay() returns the base value unchanged.
