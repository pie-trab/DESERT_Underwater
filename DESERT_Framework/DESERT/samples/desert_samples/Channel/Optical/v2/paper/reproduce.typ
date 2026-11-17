#set page(width: 16cm, height: auto, margin: 1.8cm)
#set text(size: 10pt)
#set par(justify: true)

#align(center)[
  #text(16pt, weight: "bold")[Reproduce the paper]
]

Run from the `v2` directory after sourcing the DESERT environment:

```console
source "$(git rev-parse --show-toplevel)/DESERT_buildCopy_LOCAL/environment"
cd DESERT_Framework/DESERT/samples/desert_samples/Channel/Optical/v2

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

Pilot runs are available with `--phase pilot` for distance/diagnostic/wind
and `--stage pilot` for turbidity. The end-to-end main command is
`python3 simulation/run.py all`, but it assumes the calibration step has
already been run.

Derived final data live in `simulation/data/final/`; raw logs are written to
`simulation/data/raw/` and are intentionally not committed. The paper figures
are rebuilt in `paper/figures/`, and the Typst sources stay in `paper/`.
