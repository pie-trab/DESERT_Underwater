# Paper summary and final claims

## Headline comparison

Direct acoustic vs distance-scaled plain optical, c=0.3 1/m. The acoustic equal-hop chain is a diagnostic and is excluded from the headline PDR/delay/energy claims.

## Defensible claims

1. In every feasible optical cell, scaled-hop optical delivered 100% of generated packets, while direct acoustic started to fail near 1500 m.
2. Optical has substantially lower delay and analytical energy per delivered bit than direct acoustic at the tested low load.
3. The optical advantage costs hardware: unique modems grow from 2 to 76 over 1500 m, and high-turbidity long-distance cells become infeasible under the 100-hop cap.
4. Direct acoustic is the lowest-hardware option and remains lossless through 1000 m in the configured model.
5. The acoustic equal-hop result is diagnostic only. Its non-monotonic PDR is an unresolved first-hop simulation artifact and is not evidence about acoustic range.

## Key numbers

- 100 m direct acoustic: PDR 100%, delay 0.150 s, energy 1303.5 uJ/bit.
- 100 m optical: delay 0.015 s, energy 64.9 uJ/bit.
- 1000 m direct acoustic: delay 1.110 s, energy 1303.5 uJ/bit.
- 1000 m optical: delay 0.160 s, energy 648.6 uJ/bit, 51 unique modems.
- 1500 m direct acoustic: PDR 27%, delay 2.036 s.
- 1500 m optical: PDR 100%, 76 unique modems.

## Required caveats

- Energy is analytical from MAC TX/RX counts and assumed powers, not simulated modem energy.
- The optical channel is deterministic; no fading, turbulence or independent misalignment is modeled.
- Beam-LUT mode is excluded.
- The acoustic equal-hop PDR is diagnostic only; its exact first-hop loss mechanism is unproven.
- The M1/M2 `2*hops` modem value is a link-endpoint count; this paper uses `hops+1` unique modems.
