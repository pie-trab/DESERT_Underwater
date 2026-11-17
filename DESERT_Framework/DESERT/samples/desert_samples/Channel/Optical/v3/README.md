# v3: dual-modem optical relay nodes

v3 reruns the v2 acoustic/optical comparison with a more realistic optical
node: every relay is a single physical box that contains **two independent
optical modems**, one facing upstream (receive) and one facing downstream
(transmit).  The source and sink keep one modem each, so a chain with `n`
relay boxes has `2n + 2` optical modems instead of v2's `n + 2`.

The model uses only stock DESERT modules.  The two heads of a relay share one
IP address and one routing table through
`Module/UW/MULTI_DESTINATION` (`DESERT_Addons/uwmulti_destination`), which
selects the downstream head for every outgoing packet and passes packets from
either head up to IP.  The relay hand-over is ordinary IP forwarding inside
one node: there is no second DESERT node per relay, no synthetic 1 m water
gap, and no extra optical hop.

## Why v2 did not do this first

v2 explicitly chose single-head relays.  The first-generation script
(`original/multi_hop_optical_tdma.tcl`) did model two heads, but as **two
separate DESERT nodes** joined by a simulated 1 m optical water hop.  That
implementation had four costs:

1. the simulated chain length was twice the number of physical relay boxes;
2. every relay needed two TDMA slots, halving its service share and lengthening
   the frame;
3. the intra-relay link needed an artificial water attenuation for a
   connection that is electrical in a real box;
4. every second hop edge in the metrics was that fake gap, not a physical
   water link.

v2 avoided those artifacts by collapsing the relay to one modem that receives
and transmits with the same head.  That is a clean abstraction, but a
narrow-beam optical head cannot point at two opposite neighbours at once.

v3 removes the artifacts rather than the hardware: one node per relay box, two
modem stacks under one IP layer, internal forwarding instead of a gap, and
edge metrics that count water hops only.  The full rationale and the model
limits are in [`docs/DESIGN.md`](docs/DESIGN.md).

## Headline result

At the v2 working point (`c = 0.3 1/m`, 20 m hop, 100 s, 10 seeds):

| Distance | v2 single-head | v3 dual-head |
| ---: | ---: | ---: |
| 100 m | 100%, 0.0149 s, 65 uJ/bit active, 6 modems | 100%, 0.0149 s, 65 uJ/bit active, 10 modems |
| 1,000 m | 100%, 0.1602 s, 649 uJ/bit active, 51 modems | 100%, 0.1602 s, 649 uJ/bit active, 100 modems |
| 1,500 m | 100%, 0.2393 s, 973 uJ/bit active, 76 modems | 100%, 0.2393 s, 973 uJ/bit active, 150 modems |

The dual-head node reproduces the single-head PDR, delay, active energy and
frame duration **exactly** at every seed and distance.  The per-head counters
show the split cleanly: every relay's upstream head reports `rx = N, tx = 0`
and every downstream head reports `tx = N, rx = 0`.  The reason for the
performance equality is that TDMA already time-separates reception and
transmission; the relay does not need a second slot for its receive-only
head.  What doubles is the hardware
count and, if the second modem is powered for the whole mission, the idle
energy.  At 1.5 km the analytical idle component rises from 0.587 to
1.159 J/bit (2.0x) for a 1.5 W powered-idle assumption; `main_results.csv`
reports the per-run mean, which is 1.209 J/bit because it averages per-run
ratios.

Full-duplex relaying (receiving and transmitting in the same slot) is **not**
claimed: the plain optical model has no head-direction isolation, so two
colocated heads active at once would interfere at distance zero.  v3 is the
conservative, schedulable dual-head model.

## Layout

```text
v3/
├── simulation/
│   ├── run.py                 single entry point
│   ├── core.py                scenario launch and metric parsing
│   ├── distance.py            acoustic / single / dual distance sweep
│   ├── load.py                offered-load sweep, acoustic/single/dual
│   ├── turbidity.py           1,000 m single vs dual at c = 0.1/0.3/0.5
│   ├── energy.py              active + idle energy sensitivity
│   ├── check.py, check.sh     dataset and equality validation
│   ├── scenarios/
│   │   ├── acoustic_direct.tcl     v2 acoustic baseline
│   │   ├── optical_chain.tcl       v2 single-head baseline
│   │   └── optical_chain_dual.tcl  v3 dual-head relay
│   └── data/
│       ├── final/             derived tables, calibration and parameters
│       └── raw/               logs, git-ignored
├── docs/
│   └── DESIGN.md              node model, rationale, limitations
└── README.md
```

## Commands

From this directory, after sourcing the DESERT build environment:

```console
source "$(git rev-parse --show-toplevel)/DESERT_buildCopy_LOCAL/environment"
python3 simulation/run.py distance --phase main
python3 simulation/run.py load
python3 simulation/run.py turbidity
python3 simulation/run.py energy
PYTHON=python3 simulation/check.sh
```

System `python3` may not have pandas; use a venv with `pandas` installed and
set `PYTHON` to its interpreter for `check.sh`.

`distance --phase pilot` is a two-seed, 20 s smoke test.  The main sweep is
10 seeds and 100 s at 50, 100, 200, 500, 1,000 and 1,500 m for the acoustic
direct link, the v2 single-head optical chain and the v3 dual-head chain.

Like v2, the derived `*.csv` files under `simulation/data/final/` are caught
by the repo-wide `*.csv` ignore rule.  Use `git add -f` on the ones that
should be committed; `simulation/data/raw/` is intentionally untracked.
