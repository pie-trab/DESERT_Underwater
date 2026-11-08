#set page(width: 16cm, height: auto, margin: 1.8cm)
#set text(size: 10pt)
#set par(justify: true)

#align(center)[
  #text(16pt, weight: "bold")[
    Reproduce the M5 manuscript
  ]
]

From the repository root, after sourcing the DESERT environment:

```console
source /home/pietro/DESERT_Underwater/DESERT_buildCopy_LOCAL/environment
cd DESERT_Framework/DESERT/samples/desert_samples/Channel/Optical/v2

python3 run_m1.py --pilot-only
python3 run_m1.py --main-only

python3 run_m2.py --part-a
python3 run_m2.py --calibration-pilot
python3 run_m2.py --grid-pilot
python3 run_m2.py --main
python3 run_m2.py --energy

python3 run_m3.py --pilot
python3 run_m3.py --main
python3 run_m3.py --paper

python3 run_m4.py --paper

checks/milestone1.sh
checks/milestone2.sh
checks/milestone3.sh
checks/milestone4.sh
checks/milestone5.sh
```

Raw per-run logs and result CSVs are intentionally not committed. The
committed derived outputs are summaries, frozen parameter tables, paper
figures and the Typst manuscript.
