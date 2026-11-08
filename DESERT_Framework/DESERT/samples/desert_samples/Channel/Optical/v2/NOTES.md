# Experiment notes

## Baseline

- Ran the unchanged current runner with its default full grid:
  5 sweeps, 37 sweep points, 3 technologies, 30 RNG substreams, and a
  1000 s stop time: 3330 simulations.
- Output was written to `results_current_baseline/`; the pre-existing
  `results/` dataset was not overwritten.
- The baseline completed with 3330 rows and zero failed runs.

The exact baseline values were: distance = 20, 40, 60, 80, 100, 200, 500,
1000, 1200, 1300, 1400, 1500, 1600 m; relay count at fixed 100 m = 1, 2, 3,
4, 5; offered-load period = 0.005, 0.01, 0.02, 0.05, 0.1, 0.25, 0.5,
1.0 s; payload = 64, 125, 250, 500 bytes; turbidity c = 0.1, 0.3, 0.5,
0.8, 1.2, 1.6, 2.0 1/m. Every value was run for acoustic, plain optical
and beam optical with 30 RNG substreams.

## Diagnostic instrumentation

- Added one effective-configuration line to each v2 Tcl script. It prints the
  instantiated PHY, channel and propagation class names, plus the values
  passed to the PHY and TDMA configuration.
- This is output-only instrumentation; no simulation behavior or parameter
  value was changed.

- A 20 s, one-seed diagnostic run will exercise acoustic, plain optical and
  beam optical at 50 m total distance (two optical relays; 16.667 m optical
  hops) to verify that the added lines execute and identify the instantiated
  classes.
- The first manual diagnostic launch used an incorrect relative path for the
  environment file and failed before `ns` started; it was corrected to the
  repository-local absolute environment path, with no simulation result
  produced by the failed launch.
- Successful diagnostic configuration: `n_relays=2`, `cbr_period=0.25`,
  `packet_size=125`, total distance 50 m, 20 s stop time, RNG substream 1;
  optical hop length 16.6667 m. Acoustic printed `Module/UW/PHYSICAL`,
  `Module/UnderwaterChannel`, `MPropagation/Underwater`; plain optical
  printed `Module/UW/OPTICAL/PHY`, `Module/UW/Optical/Channel`,
  `Module/UW/OPTICAL/Propagation`; beam optical printed
  `Module/UW/UWOPTICALBEAMPATTERN` with the same optical channel and
  propagation classes. All three delivered every generated packet in this
  short clear-water run.

## Planned pilot and focused runs

- Pilot: 2 RNG substreams and 20 s stop time around the optical distance,
  offered-load, turbidity and optical-divergence transitions.
- Focused: 10 RNG substreams and 100 s stop time around the transitions found
  by the pilot. The tested grids will be recorded here before execution.
- No Tcl physical parameter will be tuned to force a desired result. Any
  added divergence-angle test is a sensitivity experiment because the v2
  model exposes divergence (`theta`), not a true independent node-misalignment
  parameter.

The explicit grids supplied by `focused_comparison.py` are:

| phase | sweep | values | fixed configuration |
|---|---|---|---|
| pilot | distance | 60, 70, 80, 90, 100, 110 m | 2 relays, cbr period 0.25 s, theta 0.524 |
| pilot | offered load | periods 0.04, 0.05, 0.075, 0.1, 0.125, 0.15 s | 2 relays, 50 m |
| pilot | turbidity | c = 0.5, 0.6, 0.7, 0.8, 1.0, 1.2, 1.6, 2.0 1/m | 2 relays, 50 m |
| pilot | divergence | theta = 0.174, 0.262, 0.349, 0.524, 0.698 rad | 2 relays, 60 m |
| focused | distance | 65, 70, 75, 80, 85, 90, 95, 100, 105 m | 2 relays, cbr period 0.25 s |
| focused | offered load | periods 0.04, 0.05, 0.06, 0.075, 0.1, 0.125, 0.15, 0.2 s | 2 relays, 50 m |
| focused | turbidity | c = 0.5, 0.6, 0.7, 0.8, 1.0, 1.2, 1.4, 1.6, 2.0 1/m | 2 relays, 50 m |
| focused | divergence | theta = 0.174, 0.262, 0.349, 0.524, 0.698 rad | 2 relays, 60 m |

## Completed focused runs

- Pilot completed: 150 rows (4 sweeps × listed values × 3 technologies × 2
  seeds), zero failures.
- Focused completed: 930 rows (4 sweeps × listed values × 3 technologies ×
  10 seeds), zero failures.
- The distance pilot located the plain-optical transition at a 26.667 m hop
  (80 m total with two relays) and the beam transition at a 30 m hop (90 m
  total). The focused run confirms these as deterministic threshold cliffs.
- The load pilot/focused run shows different service ceilings: approximately
  10 packets/s acoustic and 20 packets/s optical under the configured TDMA
  settings.
- The divergence sweep produced no measurable change for 20 m optical hops;
  this is a negative result, not evidence that the model implements node
  misalignment. v2 fixes beam inclination at zero and exposes no independent
  misalignment parameter.

## Milestone 1 implementation notes

- Milestone 1 uses a common fixed guard of 1 ms and one packet per TDMA slot
  for both technologies. The derived slot is
  `slot = 8*(payload + CBR + UDP + IP header bytes)/bitrate + hop/speed +
  guard`; the frame is `TDMA slot count * slot`, with slot count equal to
  simulator nodes. Header sizes are queried from the loaded DESERT modules.
- The low-load period is 5.0 s (Poisson mean, 0.2 packet/s). It is chosen to
  remain below the acoustic service rate even at 1500 m while preserving a
  measurable delay comparison.
- The plain-optical clear-water hop target is 20 m. It is below the earlier
  20--26.667 m cliff interval and gives margin; the runner uses
  `hops=ceil(distance/20)` and `n_relays=hops-1`, with equal hops summing to
  the requested distance.
- The first timing smoke runs reached the new timing line but failed in the
  final diagnostic print because the old `packet_time` field had been renamed.
  No result was accepted from those runs; the compatibility field was restored
  before the pilot.

## Milestone 1 run record

- Pilot: `python3 run_m1.py --pilot-only`, 8 requested distances, 2 seeds,
  20 s, 32 rows, zero failures, zero conservation residual, maximum observed
  runtime 5.22 s.
- Main: `python3 run_m1.py --main-only`, 8 distances, 10 seeds, 100 s,
  160 rows, zero failures, zero conservation residual, maximum observed
  runtime 6.75 s. All requested distances were retained.
- The final summary and plots were regenerated from the main raw CSV after
  adding the deterministic `modems_ci95=0` column; no simulations were
  rerun for that output-only regeneration.
- At 1000 m, both technologies delivered all packets; optical mean delay was
  160 ms versus 1.11 s acoustic, and optical energy was 575 versus 1156
  uJ/bit. At 1500 m, acoustic PDR fell to 27.0+/-6.0% while optical stayed
  at 100%, but optical used 150 requested modems and 862.5 uJ/bit.
- The acoustic 1500 m degradation is the configured acoustic PER/SNR model;
  the optical result is maintained by the 20 m plain-optical hop target. The
  requested optical modem count grows linearly and is the main deployment
  cost. No C++ change was required for this milestone.

## Milestone 2 choices

- Part A uses verified copies of the M1 plots under `results_m2/part_a/` so
  the protected M1 figures are not modified. The acoustic 1500 m point is
  marked with an open marker because PDR is below 0.95; delay is conditional
  on delivered packets and energy includes transmissions of lost packets.
- Schedule expectations use the actual fair-mode TDMA behavior: optical's
  sparse source slot contributes approximately half a frame of phase wait,
  then one slot per hop; acoustic's source owns half of its two-slot frame,
  giving the first-order `slot + frame/4` phase approximation. These are
  checks against measured M1 means, not new fitted parameters.
- The calibration grid and fixed 80% working-hop rule are recorded in
  `PROGRESS.md` before any M2 simulations. The grid extends to 100 m to avoid
  declaring a low-turbidity range from an artificially short upper bound.
- M2 energy uses the full packet airtime from the saved TDMA timing fields.
  This is intentionally different from the legacy payload-only energy field
  and is reported as a recomputation, not a change to the simulator.
- The first grid pilot exposed an output-runner bug: it iterated every row of
  the calibration table instead of one selected working-hop row per c,
  producing duplicated optical cases. Those results are not accepted. The
  grid selector was corrected to `drop_duplicates('water_c')` before the
  corrected pilot/main runs.

## Milestone 2 completed runs

- Part A used no simulations. Verified M1 plots/table are under
  `results_m2/part_a/`; the schedule check passed within 10% for both
  technologies.
- Calibration pilot: 150 runs, 2 seeds, 20 s, zero failures. Selected max
  usable hops are 50, 25, 15, 10 and 5 m for c=0.1, 0.3, 0.5, 0.8 and 1.2.
- Corrected grid pilot: 54 simulations, 2 seeds, 20 s, zero failures.
- Corrected main: 270 simulations (50 acoustic reused-distance runs plus 220
  optical feasible runs), 10 seeds, 100 s, zero failures. Three optical cells
  are INFEASIBLE because they exceed 100 hops.
- `checks/milestone2.sh` passes. The baseline energy curve has no crossover;
  the joint power envelope has a 663 m crossover only in its optimistic
  acoustic/pessimistic optical extreme, while the distance-scaled acoustic
  TX sensitivity has no crossover and grows very large.

## Milestone 3 choices and runs

- The acoustic equal-hop control uses the same single-head relay chain and
  the same TDMA derivation as the optical chain. It is an equal-topology
  ablation, not an acoustic deployment recommendation.
- Distances: 50, 100, 200, 500, 1000 and 1500 m. The acoustic chain uses the
  same 20 m hop target as the c=0.3 optical chain, so both relay scenarios
  have the same hop count and topology.
- Traffic is frozen at 125 byte payload, Poisson mean period 5 s and 100 s
  main runtime with 10 seeds. No physical parameter was tuned after seeing
  the results.
- The paper hardware count is corrected to unique modems (`hops + 1`), not
  the legacy `2*hops` link-endpoint count. At 1000 m this changes the optical
  figure from 100 to 51 modems.
- Pilot: 12 runs, 2 seeds, 20 s, zero failures, maximum runtime 5.59 s.
- Main: 60 runs, 10 seeds, 100 s, zero failures, maximum runtime 15.08 s.
- `checks/milestone3.sh` passes after running the M1 and M2 checks.
- Surprise: acoustic equal-hop PDR is 0.682 at 500 m and 0.586 at 1000 m,
  but 1.0 at 1500 m. Source `mac_tx` equals all generated packets, all lost
  packets are missing at the first hop, all downstream edge PDRs are 1.0 and
  queue drops are zero. This is not a 20 m propagation loss. It is consistent
  with a TDMA slot-boundary/forwarding artifact and is documented as a model
  limitation in `M3_FINDINGS.md`; it must not be interpreted as acoustic
  range behavior.
- Paper assets are under `results_m3/paper/`; the freeze includes the
  c=0.3 distance baseline, M2 turbidity maps, unique-modem counts and the
  M2 energy sensitivity. No beam mode or misalignment study was added.

## Milestone 4 choices

- M4 is output-only; no new benchmark simulations and no physical parameter
  changes.
- The acoustic equal-hop PDR is quarantined as diagnostic-only. The saved
  counters localize loss to the first hop and rule out acoustic range loss,
  but do not prove the exact simulator mechanism. Final paper wording is
  therefore "first-hop simulation artifact; mechanism unresolved."
- The headline comparison is restricted to direct acoustic vs optical
  scaled-hop. The acoustic chain appears only in a separate diagnostic
  figure and table.
- Hardware counts in the final paper use unique modems (`hops + 1`). The M1/M2
  `2*hops` value remains documented as a link-endpoint convention.
- Final assets are under `results_m4/paper/`; `REPRODUCE.md` lists the full
  command sequence and `checks/milestone4.sh` verifies the package.
