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
source /home/pietro/DESERT_Underwater/DESERT_buildCopy_LOCAL/environment
python3 simulation/run.py paper
simulation/check.sh
```

For the full simulation pipeline, see `docs/EXPERIMENT.md` or
`paper/reproduce.typ`.
