# v2: consolidated acoustic/optical study

This folder contains the final simulation, data and Typst paper for the
underwater acoustic versus scaled-hop optical comparison.

- `simulation/run.py` — single entry point for all simulation and analysis
  stages.
- `simulation/data/final/` — committed derived results used by the paper.
- `simulation/data/raw/` — generated logs, intentionally ignored.
- `paper/` — Typst manuscript, figures, tables and reproduction notes.
- `docs/EXPERIMENT.md` — method, final results and limitations.

Quick commands from this directory:

```console
source "$(git rev-parse --show-toplevel)/DESERT_buildCopy_LOCAL/environment"
python3 simulation/run.py wind --phase main
python3 simulation/run.py wind --phase step
python3 simulation/run.py ambient
python3 simulation/run.py replication
python3 simulation/run.py load
python3 simulation/run.py robustness
python3 simulation/run.py beam-check
python3 simulation/run.py paper
simulation/check.sh
```

For the full simulation pipeline, see `docs/EXPERIMENT.md` or
`paper/reproduce.typ`.

The dual-modem relay variant is in `../v3/`; it is simulation-only and keeps
the v2 single-head chain as its baseline. See `../v3/docs/DESIGN.md` for why
v2 chose the single-head abstraction and what the dual-head model changes.
