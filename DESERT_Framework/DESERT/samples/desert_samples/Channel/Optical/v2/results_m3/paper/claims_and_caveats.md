# Paper claims and caveats

## Defensible claims

1. In the feasible optical region, scaled-hop optical delivers all packets with much lower delay and analytical energy per delivered bit than direct acoustic communication.
2. The optical advantage is not free: unique relay hardware grows with distance and with turbidity, and three high-turbidity/long-distance cells are infeasible under the 100-hop cap.
3. The acoustic equal-hop control separates technology from topology: relaying an acoustic packet through the same number of hops is much slower and more energy-intensive than the optical chain.
4. Direct acoustic remains the lowest-hardware option and is lossless through 1000 m in the configured model; it degrades near 1500 m.

## Key numbers

- At 100 m: direct acoustic delay 0.150 s, acoustic chain 0.494 s, optical 0.015 s.
- At 1000 m: direct acoustic delay 1.110 s, acoustic chain 8.842 s, optical 0.160 s.
- At 1000 m, unique modems: direct acoustic 2, acoustic chain 51, optical 51.
- Acoustic-chain PDR is 0.68 at 500 m and 0.59 at 1000 m; the loss is recorded at the first hop while all downstream edges are 1.0, so it is a TDMA slot-boundary artifact rather than range loss.

## Caveats

- Energy is analytical from MAC TX/RX event counts and assumed powers, not simulated modem energy. The +/-50% power envelope and the distance-scaled acoustic TX case are sensitivity analyses.
- The optical channel is deterministic threshold behavior: no time-varying fading, turbulence, or independent node misalignment.
- Beam-LUT mode is excluded from the paper dataset.
- The acoustic chain is an equal-topology ablation, not an acoustic deployment recommendation. Its non-monotonic PDR at 500/1000 m is a model artifact and must not be read as a physical range curve.
- The M1/M2 `2*hops` modem count is a link-endpoint count; the paper uses `hops+1` unique modems and reports both in the derived data.
