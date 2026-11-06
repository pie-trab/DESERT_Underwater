# Acoustic vs. multi-hop optical benchmark

Two generations of the same study live here. `original/` is the first
notebook-driven workflow; `v2/` is the redesigned, script-driven benchmark.
They are kept separate on purpose: the models, the Tcl scripts and the
outputs are not interchangeable.

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
└── v2/                        redesigned benchmark
    ├── run_comparison_v2.py
    ├── analyze_v2.py
    ├── multi_hop_optical_v2.tcl
    ├── single_link_acoustic_v2.tcl
    ├── results/               generated data (13 MB, plots tracked)
    └── reports/               local write-up (git-excluded)
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

```console
$ source <install-dir>/environment
$ cd v2
$ python3 run_comparison_v2.py                 # full 2 610-run grid -> results/
$ python3 run_comparison_v2.py --quick         # 87-run smoke test
$ python3 analyze_v2.py                        # consistency checks + tables
```

`v2/results/` holds the revised dataset (Rev. 2, 3 330 runs: 111 sweep
points × 3 technologies × 30 RNG substreams — the distance sweep now reaches
1 600 m and the acoustic PHY uses a 0 dB acquisition threshold), plus
summary, per-run logs and the five `v2_*.png` figures. The earlier
generations are archived untouched:
`results_cbr0.25/` (original 2 610-run dataset, 15 dB acoustic threshold)
and `results_cbr0.05/` (stress experiment with base CBR period 0.05 s).

## Notes

- The `.md` reports under `original/reports/` and `v2/reports/` are
  deliberately excluded in `.git/info/exclude` and are never pushed.
- Everything below `original/results/` is excluded as well; the tracked
  PNG sets there were committed before the reorganization.
- The two Tcl generations expect different argument lists and different
  metrics blocks. Do not mix their runners and scripts.
