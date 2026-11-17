#!/usr/bin/env python3
"""Single entry point for the v3 dual-head optical study."""

from __future__ import annotations

import argparse

import distance
import energy
import load
import turbidity


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run or analyze the v3 dual-head optical experiment.")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("distance", help="acoustic/single/dual distance sweep")
    p.add_argument("--phase", choices=("pilot", "main"), default="main")

    sub.add_parser("load",
                   help="offered-load sweep, single vs dual optical")
    sub.add_parser("turbidity",
                   help="1,000 m single vs dual at three turbidity values")
    sub.add_parser("energy", help="recompute analytical energy sensitivity")
    sub.add_parser("all", help="run distance, load, turbidity and energy")

    args = parser.parse_args()
    if args.command == "distance":
        distance.run(args.phase)
    elif args.command == "load":
        load.run()
    elif args.command == "turbidity":
        turbidity.run()
    elif args.command == "energy":
        energy.run()
    elif args.command == "all":
        distance.run("main")
        load.run()
        turbidity.run()
        energy.run()


if __name__ == "__main__":
    main()
