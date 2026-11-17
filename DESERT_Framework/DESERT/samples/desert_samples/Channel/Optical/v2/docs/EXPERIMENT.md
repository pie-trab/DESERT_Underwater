# Underwater acoustic versus optical experiment

This directory is the single consolidated study for the acoustic-versus-optical
comparison. It contains the simulation code, final derived data, validation,
and the Typst paper.

## Layout

```text
v2/
├── simulation/
│   ├── run.py                 single entry point
│   ├── core.py                scenario launch and metric parsing
│   ├── distance.py            distance sweep
│   ├── turbidity.py           calibration and turbidity grid
│   ├── diagnostic.py          acoustic equal-hop diagnostic
│   ├── wind.py                acoustic wind-speed sensitivity
│   ├── ambient.py             5/10/20 m ambient-light pilot
│   ├── replication.py         25-seed long-distance validation
│   ├── load.py                offered-load sweep
│   ├── robustness.py          guard and hop-margin checks
│   ├── beam_check.py          plain vs beam-LUT comparison
│   ├── energy.py              analytical energy sensitivity
│   ├── paper.py               final tables and figures
│   ├── check.sh               consolidated validation
│   ├── scenarios/
│   │   ├── acoustic_direct.tcl
│   │   ├── optical_chain.tcl
│   │   └── acoustic_chain.tcl
│   └── data/
│       ├── final/             committed derived tables
│       └── raw/               generated logs, ignored
├── paper/
│   ├── abstract.typ
│   ├── paper.typ
│   ├── reproduce.typ
│   ├── abstract_claims.csv
│   ├── figures/
│   └── tables/
├── docs/
│   └── EXPERIMENT.md
└── README.md
```

## Scenarios

- **Direct acoustic:** two modems separated by the source--destination
  distance.
- **Optical scaled-hop:** a horizontal chain of single-head optical modems.
  At `c = 0.3 1/m` the hop is 20 m, which is 80% of the measured 25 m
  baseline shallow-coastal reach.
- **Acoustic equal-hop diagnostic:** the same chain topology and hop count as
  the optical case, using the standard acoustic PHY. Its PDR is diagnostic
  only because first-hop losses are a simulation artifact.

## Common method

- DESERT with the standard UDP/IP/static-routing/MLL/TDMA stack.
- One packet per TDMA slot and a common 1 ms guard.
- Slot duration:

  `slot = 8*(payload + CBR + UDP + IP headers)/bitrate + hop/speed + guard`.

- Frame duration: `slot * number of simulator nodes`.
- Traffic: 125-byte payload, Poisson arrivals with 5 s mean period.
- Main runtime: 100 s, 10 RNG substreams.
- Metrics: destination-MAC PDR, sink forward-trip delay, goodput over the
  traffic window, analytical TX+RX energy per delivered bit, unique modems,
  packet conservation.

## Commands

From this directory, after `source <build>/environment`:

```console
python3 simulation/run.py distance --phase main
python3 simulation/run.py turbidity --stage calibrate
python3 simulation/run.py turbidity --stage main
python3 simulation/run.py diagnostic --phase main
python3 simulation/run.py wind --phase main
python3 simulation/run.py wind --phase step
python3 simulation/run.py ambient
python3 simulation/run.py replication
python3 simulation/run.py load
python3 simulation/run.py robustness
python3 simulation/run.py beam-check
python3 simulation/run.py energy
python3 simulation/run.py paper
simulation/check.sh
```

Pilot variants use `distance --phase pilot`, `diagnostic --phase pilot`,
`wind --phase pilot`, or `turbidity --stage pilot`. `simulation/run.py all`
runs the main distance, turbidity, diagnostic, wind, energy, and paper stages;
calibration must exist first. `wind --phase step`, `ambient`, `replication`,
`load`, `robustness` and `beam-check` are separate fixed-value checks.

## Final results

At `c = 0.3 1/m`:

| Distance | Direct acoustic | Optical scaled-hop |
|---:|---|---|
| 100 m | 100%, 0.735 s, 10,828.8 uJ/bit, 2 modems | 100%, 0.0149 s, 64.9 uJ/bit, 6 modems |
| 1,000 m | 100%, 2.084 s, 10,828.8 uJ/bit, 2 modems | 100%, 0.160 s, 648.6 uJ/bit, 51 modems |
| 1,500 m | 100%, 2.840 s, 10,828.8 uJ/bit, 2 modems | 100%, 0.239 s, 972.9 uJ/bit, 76 modems |

Both links are lossless at the headline load. The optical chain wins delay,
energy and load capacity, but its unique modem count grows with distance and
turbidity. Direct acoustic remains the low-hardware option, at the cost of
delay and energy.

## Wind sensitivity

The plain optical model has no wind-speed input; the wind sweep therefore
applies to the acoustic link. With the hardware-matched acoustic PHY, PDR is
100% and delay is unchanged from 0 to 20 m/s at 500, 1,000 and 1,500 m; a
1 m/s step from 5 to 14 m/s at 1.5 km is also flat. The earlier 50 kHz
baseline showed 100, 100, 27, 0 and 0% at 0, 5, 10, 15 and 20 m/s at 1.5 km;
that was a high-absorption parameter artifact, not a hardware-independent
wind limit.

## Turbidity

Measured maximum single-hop reach with PDR >= 0.95 and the fixed 80% working
hop:

| c (1/m) | max hop | working hop |
|---:|---:|---:|
| 0.1 | 50 m | 40 m |
| 0.3 | 25 m | 20 m |
| 0.5 | 15 m | 12 m |
| 0.8 | 10 m | 8 m |
| 1.2 | 5 m | 4 m |

Optical cells `c=0.8/D=1000 m`, `c=1.2/D=500 m` and `c=1.2/D=1000 m` exceed
the 100-hop cap and are marked INFEASIBLE.

## Energy

Energy is analytical from MAC TX/RX event counts and configured airtime. The
baseline assumptions are 20 W TX / 4 W RX for acoustics and 10 W TX / 1.5 W RX
for optics. Optical is lower at every distance in the baseline and in both
±50% envelope extremes; there is no crossover. The distance-scaled acoustic TX
case is a sensitivity warning, not a calibrated modem model.

## Acoustic equal-hop diagnostic

The acoustic equal-hop chain is lossless at all distances with the
hardware-matched PHY, but its delay grows from 2.58 s at 50 m to 391 s at
1,500 m because 76 modems share a 2.5 kbit/s TDMA frame. The former first-hop
loss does not appear in this configuration. The chain is excluded from the
headline claims because it is a topology diagnostic, not a deployment
alternative.

## Limitations

- Analytical energy assumptions; not measured modem power.
- Deterministic optical threshold channel; no fading, turbulence or
  independent misalignment.
- Beam-LUT mode excluded: it replaces the SNR threshold with a max-range gate,
  uses 5 Mbit/s/531.5--532 nm tables against a 1 Mbit/s/395 nm PHY, and the
  Y-axis chain gives a constant azimuth factor. At `c=0.1` its gate is below
  the 40 m working hop, so its results would be artifacts.
- Wind sensitivity is acoustic-only and is flat at the hardware-matched
  operating point; the plain optical model has no wind input.
- The 50 kHz / 180 dB / spreading-2 acoustic case is a parameter sensitivity,
  not the baseline; it gives 27% at 1.5 km while the hardware-matched case is
  lossless.
- Turbid harbor `c=2.19` has a 1.6 m working hop, below the 2 m minimum; all
  harbor cells are INFEASIBLE.
- Horizontal chain at a shared depth.
- CBR sequence-wrap avoided by the selected low load.
- Simulation study of configured models, not a field trial.

## Current status

- The study is consolidated into `simulation/`, `paper/` and `docs/`;
  intermediate result trees and legacy entry points were removed.
- The final derived dataset and paper figures are generated, including the
  hardware-matched acoustic baseline, wind step, ambient pilot, 25-seed
  replication, load sweep, guard/hop-margin checks and beam-mode check.
- `simulation/check.sh` validates data, numbers, manuscript structure and
  claim separation.
- The Typst manuscript source is provided; Typst is installed in this
  environment and the report builds locally.
- Author-supplied items remain: verified bibliography entries, author names
  and affiliation, and target-venue formatting.
