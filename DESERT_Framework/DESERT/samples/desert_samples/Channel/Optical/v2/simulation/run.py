#!/usr/bin/env python3
"""Single entry point for the underwater acoustic/optical study."""

from __future__ import annotations

import argparse
from pathlib import Path

import core
import ambient
import beam_check
import diagnostic
import distance
import energy
import load
import paper
import replication
import robustness
import turbidity
import wind


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run or analyze the consolidated underwater experiment.")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("distance", help="distance sweep")
    p.add_argument("--phase", choices=("pilot", "main"), default="main")

    p = sub.add_parser("turbidity", help="turbidity calibration/grid")
    p.add_argument("--stage", choices=("calibrate", "pilot", "main"),
                   default="main")

    p = sub.add_parser("diagnostic", help="acoustic equal-hop diagnostic")
    p.add_argument("--phase", choices=("pilot", "main"), default="main")

    p = sub.add_parser("wind", help="acoustic wind-speed sensitivity")
    p.add_argument("--phase", choices=("pilot", "main", "step"),
                   default="main")

    sub.add_parser("beam-check",
                   help="compare plain and beam-LUT optical modes")
    sub.add_parser("ambient", help="ambient-light optical pilot")
    sub.add_parser("replication",
                   help="25-seed validation at 1,000/1,500 m")
    sub.add_parser("load", help="offered-load sweep at 1,000/1,500 m")
    sub.add_parser("robustness",
                   help="optical guard and hop-margin sensitivity")
    sub.add_parser("energy", help="recompute energy sensitivity")
    sub.add_parser("paper", help="rebuild paper tables and figures")
    sub.add_parser("all", help="run the main pipeline end to end")

    args = parser.parse_args()
    if args.command == "distance":
        distance.run(args.phase)
    elif args.command == "turbidity":
        if args.stage == "calibrate":
            turbidity.calibrate()
        else:
            turbidity.grid(args.stage)
    elif args.command == "diagnostic":
        diagnostic.run(args.phase)
    elif args.command == "wind":
        wind.run(args.phase)
    elif args.command == "beam-check":
        beam_check.run()
    elif args.command == "ambient":
        ambient.run()
    elif args.command == "replication":
        replication.run()
    elif args.command == "load":
        load.run()
    elif args.command == "robustness":
        robustness.run()
    elif args.command == "energy":
        energy.run()
    elif args.command == "paper":
        paper.build()
    elif args.command == "all":
        if not (core.FINAL / "calibration.csv").exists():
            turbidity.calibrate()
        distance.run("main")
        turbidity.grid("main")
        diagnostic.run("main")
        wind.run("main")
        wind.run("step")
        ambient.run()
        replication.run()
        load.run()
        robustness.run()
        beam_check.run()
        energy.run()
        paper.build()


if __name__ == "__main__":
    main()
