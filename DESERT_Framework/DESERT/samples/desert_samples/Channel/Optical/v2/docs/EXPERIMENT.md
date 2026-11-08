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
  clear-water reach.
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
python3 simulation/run.py energy
python3 simulation/run.py paper
simulation/check.sh
```

Pilot variants use `distance --phase pilot`, `diagnostic --phase pilot`, or
`turbidity --stage pilot`. `simulation/run.py all` runs the main distance,
turbidity, diagnostic, energy, and paper stages; calibration must exist first.

## Final results

At `c = 0.3 1/m`:

| Distance | Direct acoustic | Optical scaled-hop |
|---:|---|---|
| 100 m | 100%, 0.150 s, 1,303.5 uJ/bit, 2 modems | 100%, 0.0149 s, 64.9 uJ/bit, 6 modems |
| 1,000 m | 100%, 1.110 s, 1,303.5 uJ/bit, 2 modems | 100%, 0.160 s, 648.6 uJ/bit, 51 modems |
| 1,500 m | 27.0 +/- 4.3%, 2.036 s, 2 modems | 100%, 0.239 s, 76 modems |

The optical chain is lossless in every feasible modeled cell, but its unique
modem count grows with distance and turbidity. Direct acoustic remains the
low-hardware option through 1 km and degrades near 1.5 km.

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
for optics. The +/-50% power envelope has no crossover in the conservative
case and an interpolated crossover at about 663 m in the optimistic
acoustic/pessimistic optical extreme. The distance-scaled acoustic TX case is
a sensitivity warning, not a calibrated modem model.

## Diagnostic artifact

The acoustic equal-hop chain is not a physical PDR curve. Losses occur at the
first hop while every downstream edge is 1.0 and queues are empty; the first
hop is an ideal 20 m link. The exact simulator mechanism is unresolved, so the
curve is excluded from headline claims.

## Limitations

- Analytical energy assumptions; not measured modem power.
- Deterministic optical threshold channel; no fading, turbulence or
  independent misalignment.
- Beam-LUT mode excluded.
- Horizontal chain at a shared depth.
- CBR sequence-wrap avoided by the selected low load.
- Simulation study of configured models, not a field trial.

## Current status

- The study is consolidated into `simulation/`, `paper/` and `docs/`;
  intermediate result trees and legacy entry points were removed.
- The final derived dataset and paper figures are committed.
- `simulation/check.sh` validates data, numbers, manuscript structure and
  claim separation.
- The Typst manuscript source is provided; the `typst` binary is not
  installed in this environment, so no PDF was compiled locally.
- Author-supplied items remain: verified bibliography entries, author names
  and affiliation, and target-venue formatting.
