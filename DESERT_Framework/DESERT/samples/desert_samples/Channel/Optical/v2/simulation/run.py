#!/usr/bin/env python3
"""Single entry point for the underwater acoustic/optical study."""

from __future__ import annotations

import argparse
from pathlib import Path

import core
import diagnostic
import distance
import energy
import paper
import turbidity


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
        energy.run()
        paper.build()


if __name__ == "__main__":
    main()
