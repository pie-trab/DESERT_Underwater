# Milestone 2 findings

## Part A: M1 verification

The full PDR table is in `results_m2/part_a/pdr_table.csv`. Every M1 point
has PDR 1.0 except acoustic at 1500 m: **0.270 +/- 0.043** (95% CI). At that point delay is
computed only over delivered packets and energy/bit includes the energy of
TX/RX events for packets that were lost. It is therefore not undefined. The
verified copies of the M1 plots use an open marker for this point.

At 1000 m the saved schedule gives:

| technology | hops | slot | frame | expected delay | measured delay |
|---|---:|---:|---:|---:|---:|
| optical | 50 | 2.128 ms | 108.533 ms | 160.671 ms | 160.230 ms |
| acoustic | 1 | 721.981 ms | 1.443962 s | 1.083 s | 1.110 s |

The optical expectation is 50 service slots plus half a frame for source-slot
phase. The acoustic expectation is one service slot plus the first-order
quarter-frame phase term for a source owning half of the two-slot frame. Errors
are 0.3% and 2.5%, respectively. The schedules use the same derivation and
one-packet-slot rule, but their frame lengths differ necessarily because the
optical path has 51 simulator nodes and the acoustic path has two.

## Part B: calibrated scaled-hop turbidity

| c (1/m) | max pilot hop with both seeds PDR >= 0.95 | working hop (80%) |
|---:|---:|---:|
| 0.1 | 50 m | 40 m |
| 0.3 | 25 m | 20 m |
| 0.5 | 15 m | 12 m |
| 0.8 | 10 m | 8 m |
| 1.2 | 5 m | 4 m |

The calibration pilot used 150 runs, two seeds and 20 s per case. The corrected
scaled-grid pilot used 10 acoustic plus 44 optical runs; the corrected main
run used 50 acoustic plus 220 optical runs. All completed with zero failures
and zero conservation residuals. The first grid pilot was discarded because
the runner iterated the full calibration table instead of one selected row per
water type; no values from it are used here.

The only infeasible optical cells are:

- c=0.8, D=1000 m: 125 hops;
- c=1.2, D=500 m: 125 hops;
- c=1.2, D=1000 m: 250 hops.

All feasible optical cells achieved PDR 1.0 in the main run. Consequently,
the delay and energy regime maps are clean deployment-cost maps rather than
loss-conditioned maps. Every feasible cell favors optical under the baseline
assumptions: acoustic/optical delay and energy ratios are both greater than 1.
The three cells above are explicitly labelled INFEASIBLE rather than treated
as zero-performance optical points.

## Part C: energy sensitivity

Energy was recomputed from saved M1 event counts and the full-packet airtime
printed by M1. Under baseline powers, optical has lower energy/bit at every
M1 distance; there is no crossover in 50--1500 m. The joint +/-50% power
envelope has no crossover for the conservative case (acoustic high power,
optical low power), but the optimistic acoustic/ pessimistic optical envelope
crosses at an interpolated **663 m**. This is an assumption envelope, not a
simulated result.

The distance-scaled acoustic TX sensitivity has no crossover in the swept
range and rapidly becomes enormous. That behavior is expected from the
deliberately simple spreading-plus-Thorp formula and must not be presented as
a modem power prediction. It is useful only as a sensitivity warning: energy
conclusions are dominated by the assumed power model at long range.

The ratio maps are in `results_m2/delay_ratio_map.png` and
`results_m2/energy_ratio_map.png`; values above 1 mean optical is favored.
