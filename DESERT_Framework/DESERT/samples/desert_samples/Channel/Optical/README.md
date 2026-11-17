# Acoustic vs. multi-hop optical benchmark

Three generations of the same study live here. `original/` is the first
notebook-driven workflow; `v2/` is the consolidated, script-driven study;
`v3/` is a simulation-only variant with dual-modem optical relay nodes.
They are kept separate on purpose: the models, Tcl scripts and outputs are
not interchangeable.

```
Optical/
├── original/                  first-generation benchmark
│   ├── acoustic_vs_multihop_optical_full_sweeps.ipynb
│   ├── run_optical_acoustic_comparison.py
│   ├── multi_hop_optical_tdma.tcl
│   ├── multi_hop_optical_tdma_beampattern.tcl
│   ├── single_link_comp.tcl
│   ├── multi_hop_optical_tdma_opt.yaml
│   ├── get-config.tcl
│   ├── archive/               superseded scripts and early snapshots
│   ├── results/               generated data (git-excluded)
│   └── reports/               local write-ups (git-excluded)
├── v2/                        consolidated benchmark
│   ├── simulation/            one runner, scenarios, data, check
│   ├── paper/                 Typst manuscript, figures, tables
│   ├── docs/EXPERIMENT.md     method, results, limitations
│   └── README.md
└── v3/                        dual-modem optical relay nodes
    ├── simulation/            distance/load/turbidity/energy stages
    ├── docs/DESIGN.md         node model, rationale, limitations
    └── README.md
```

## original/

`results/` keeps the historical outputs, nothing was renamed inside it:

| Path | Contents |
|---|---|
| `results/notebook_full/` | archived full notebook run (~7.8 GB) plus the tracked `comparison_*.png` plots |
| `results/runner_full_20261103/` | `run_optical_acoustic_comparison.py` full sweep (~246 MB) |
| `results/legacy_snapshots/` | older per-period PNG snapshots (~739 MB) |
| `results/optical_acoustic_comparison_results_*/` | committed per-period plot sets (the suffix is the CBR period in seconds) |
| `results/misc/out.txt` | stray console log kept for reference |

Run the notebook from `original/`. It writes to `results/notebook_rerun/`
so that the archived `results/notebook_full/` dataset is never overwritten.
A single simulation can also be run directly:

```console
$ source <install-dir>/environment
$ cd original
$ ns multi_hop_optical_tdma.tcl 1 0.25 125 25.0 1.0 -10 2
```

`multi_hop_optical_tdma_beampattern.tcl` reads the LUTs from
`../../../dbs/` (relative to `original/`). Scripts in `archive/` still use
their original working-directory assumptions and are kept only as history.

## v2/

`v2/` is the consolidated study. It contains one simulation entry point,
three scenario scripts, committed derived data and the Typst paper.

```console
$ source <install-dir>/environment
$ cd v2

$ python3 simulation/run.py distance --phase main
$ python3 simulation/run.py turbidity --stage calibrate
$ python3 simulation/run.py turbidity --stage main
$ python3 simulation/run.py diagnostic --phase main
$ python3 simulation/run.py energy
$ python3 simulation/run.py paper
$ simulation/check.sh
```

Pilot runs use `--phase pilot` or `--stage pilot`. Derived data are in
`simulation/data/final/`; raw logs go to `simulation/data/raw/` and are not
committed. The final paper is in `paper/` and is written in Typst. See
`docs/EXPERIMENT.md` for parameters, results and limitations.

## v3/

`v3/` is a simulation-only variant of `v2/`. Every relay is one physical node
with two optical modem heads (upstream receive, downstream transmit) under a
shared IP layer, instead of v2's single head. It answers the hardware-realism
question without the old two-node-per-relay artifacts: no synthetic 1 m
intra-relay water hop and no extra TDMA slot. Results are bit-identical to v2
in PDR, delay, active energy and frame duration, at twice the modem count.
See `v3/README.md` and `v3/docs/DESIGN.md`.

```console
$ source <install-dir>/environment
$ cd v3
$ python3 simulation/run.py distance --phase main
$ python3 simulation/run.py load
$ python3 simulation/run.py turbidity
$ python3 simulation/run.py energy
$ PYTHON=python3 simulation/check.sh
```

## Notes

- The `.md` reports under `original/reports/` are deliberately excluded in
  `.git/info/exclude` and are never pushed.
- Everything below `original/results/` is excluded as well; the tracked PNG
  sets there were committed before the reorganization.
- The two Tcl generations expect different argument lists and different
  metrics blocks. Do not mix their runners and scripts.
