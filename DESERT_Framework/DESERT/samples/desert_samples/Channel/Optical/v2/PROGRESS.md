# Milestone 3 progress

## Status

Part A schedule verification passed using only `results_m1`; no files under
`results_m1/`, `results_current_baseline/` or `focused_results/` were
modified. New outputs belong under `results_m3/`.

## Part A decisions

- PDR verification uses the existing 10-seed means and 95% CIs. The only
  point below 0.95 is acoustic at 1500 m: 0.270 +/- 0.060. Its delay is the
  mean over delivered packets and its energy/bit includes TX/RX events for
  packets that were lost; neither value is treated as undefined because
  delivery is nonzero.
- At 1000 m, optical uses 50 hops, slot 2.128 ms and frame 108.533 ms. The
  first-order schedule expectation is `50*slot + frame/2 = 160.671 ms`,
  versus 160.230 ms measured. Acoustic uses one hop, slot 721.981 ms and
  frame 1.443962 s. Its active-slot phase approximation is
  `slot + frame/4 = 1.083 s`, versus 1.110 s measured. Both errors are below
  10%; the schedule is like-for-like in its derivation and one-packet-slot
  rule, although the topologies necessarily have different frame lengths.

## Part B planned configurations

- Calibration water coefficients: c = 0.1, 0.3, 0.5, 0.8 and 1.2 1/m.
- Calibration pilot hop lengths: 2, 5, 10, 15, 18, 20, 22, 25, 30, 35,
  40, 50, 60, 75 and 100 m; plain optical, single hop, 2 seeds, 20 s,
  period 5 s, 125-byte packets. A hop is usable only if both pilot seeds
  reach PDR >= 0.95. The largest usable tested hop is multiplied by 0.8.
- Scaled-distance grid: c values above and D = 50, 100, 200, 500 and 1000 m.
  Acoustic is simulated once per D and reused across c. Optical uses
  `ceil(D / working_hop(c)) - 1` relays. Cases over 100 hops or below 2 m
  working hop are recorded as INFEASIBLE and not simulated.
- Part B uses the milestone-1 5 s Poisson period, 125-byte payload, 1 ms
  common guard, one packet/slot and unchanged PHY powers/rates.

## Part C decisions

- Energy is recomputed from saved M1 TX/RX event counts and the full-packet
  timing airtime printed by M1, not from the older payload-only energy field.
- The power-band envelope scales all four assumed powers jointly by 0.5 and
  1.5. This is an uncertainty envelope, not a new simulation.
- Distance-scaled acoustic TX sensitivity uses the practical spreading
  exponent 2 and Thorp absorption at the actual 50 kHz carrier:
  `Ptx(D)=20 W*(D/50 m)^2*10^(alpha_Thorp*(D-50 m)/1000/10)`;
  acoustic RX remains 4 W. The 50 m reference preserves the baseline power
  at the shortest M1 distance. Thorp's standard absorption expression is
  used with frequency in kHz (Thorp, 1967/Urick underwater acoustics model).

## Next step

Milestone 2 is complete. `checks/milestone2.sh` prints PASS. The corrected
main run used 50 acoustic and 220 optical simulations, all successful; the
first duplicated grid pilot was discarded and is not part of the conclusions.
Outputs include the PDR/schedule verification, calibrated hop table, scaled
turbidity grid, delay/energy regime maps, hardware/hop plots and energy
sensitivity/crossover table. No C++ changes were needed and there is no open
blocker. A future milestone may address acoustic multihop controls and
calibrated optical alignment/energy, but milestone 3 was not started.

## Milestone 3 final status

Milestone 3 is complete and is the final experimental milestone.

- Added the acoustic equal-hop chain (`acoustic_chain_v3.tcl`), ran a 12-run
  pilot and a 60-run main grid (10 seeds, 100 s each), zero failures and zero
  conservation residuals.
- `checks/milestone3.sh` prints PASS, including the M1 and M2 regression
  checks.
- Frozen the paper parameter set and generated all paper assets under
  `results_m3/paper/`: distance comparison, regime maps, hop/hardware plot,
  energy sensitivity, parameter table, main results and claims/caveats.
- Corrected hardware accounting to unique modems (`hops + 1`): at 1000 m,
  optical is 51 modems, not the legacy 100 link endpoints.
- Key final values at 1000 m: direct acoustic 1.110 s and 1303.5 uJ/bit;
  acoustic equal-hop 8.842 s and 65960.6 uJ/bit with PDR 0.586; optical
  scaled-hop 0.160 s and 648.6 uJ/bit with PDR 1.0.
- The acoustic-chain PDR loss at 500/1000 m is localized to the first hop
  while all downstream edges are 1.0 and queues are empty. It is reported as
  a TDMA slot-boundary model artifact, not acoustic range loss.
- No open blocker. No further simulations are needed; the next step is paper
  writing/formatting only, not milestone 4.

## Milestone 4 final status

Milestone 4 is complete and is the final paper-freeze milestone.

- Split the headline package (direct acoustic vs optical scaled-hop) from
  the acoustic-chain diagnostic package.
- The acoustic-chain PDR is excluded from headline claims and marked
  diagnostic-only while its exact first-hop mechanism remains unresolved.
- Final assets are under `results_m4/paper/`: main distance figure, separate
  chain diagnostic figure, regime maps, hop/hardware plot, energy sensitivity,
  split result tables, frozen parameters, paper summary and claims.
- Added `results_m4/REPRODUCE.md` and `checks/milestone4.sh`.
- Hardware accounting in the final package uses unique modems (`hops + 1`).
- `checks/milestone4.sh` prints PASS after the M1--M3 regression checks.
- No open blocker. No M5 is needed; remaining work is manuscript writing and
  formatting.

## Milestone 5 final status

Milestone 5 is complete and is the **final milestone**; no M6 is planned.

- Wrote the manuscript in Typst under `results_m5/manuscript/`:
  `abstract.typ` (185 words), `paper.typ` (2,533 words excluding the included
  abstract), `abstract_claims.csv`, and `REPRODUCE.typ`.
- Added `M5_FINDINGS.typ` and `checks/milestone5.sh`.
- The headline claims use direct acoustic vs optical scaled-hop only.
  The acoustic equal-hop chain remains diagnostic-only with an unresolved
  first-hop simulation artifact.
- Abstract numeric claims are machine-checked against
  `results_m4/paper/main_results.csv` and `parameters.csv`.
- All M1--M5 checks pass. Remaining author input is limited to verified
  bibliography entries, author/affiliation details and target-venue
  formatting.
