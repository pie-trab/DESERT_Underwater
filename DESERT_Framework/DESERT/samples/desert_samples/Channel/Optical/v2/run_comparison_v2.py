#!/usr/bin/env python3
"""Acoustic single link vs. optical multi-hop chain, redesigned (v2).

Experiment runner for `single_link_acoustic_v2.tcl` and
`multi_hop_optical_v2.tcl`.  It is a from-scratch companion to the older
`acoustic_vs_multihop_optical_full_sweeps.ipynb` workflow and differs in
the following deliberate ways:

Architecture (implemented in the v2 Tcl scripts)
-----------------------------------------------
* One modem per relay: no second "TX head" node and no simulated
  intra-relay water gap.  Relays are half-duplex TDMA modems forwarding
  through the IP stack, like real equipment.  TDMA slots equal the node
  count, so the frame is shorter and each relay gets twice the service
  share of the old two-head design.
* The final command-line flag of the optical script (``beam_mode``)
  switches between the plain optical PHY and the beam-pattern LUT PHY.
  Both use the SAME analytic fixed-c water model, so only the hardware
  model changes between the "optical" and "beam_optical" technologies.
* Every script ends with a machine-readable ``=== METRICS v2 ===`` block:
  CBR counters, forward-trip-time statistics, and per-node MAC counters
  (transmissions, delivered receptions, IP->MAC admissions, residual
  queue).  Queue drains are covered by a drain margin that grows with the
  chain length, so lost packets are attributable to attenuation or queue
  overflow, never to a truncated experiment tail.

Metrics (implemented here)
--------------------------
* pdr: packets delivered to the destination modem's MAC / source
  application packets.  Delivered is measured at the destination modem
  (MAC reception), which is unaffected by the DESERT CBR counter bug
  described below; the raw application count is kept as `pdr_app`.
* Never more than 1: delivered <= sent by construction.
* goodput_bps: delivered payload bits over the traffic window
  (stoptime - starttime), not the whole simulation span.
* delay_mean_s / delay_std_s: forward-trip-time statistics at the sink
  application (computed on the packets it accepts; censored runs, see
  below, only measure the pre-wrap part of the run).
* Per-edge PDRs aligned to physical links: edge h is transmission of
  modem h received by modem h+1; we report both the mean and the weakest
  edge (the classic multi-hop bottleneck metric).
* Queue-drop accounting per node (IP->MAC admissions minus actual PHY
  transmissions, minus the residual queue) so losses can be located at a
  specific modem, plus `phy_lost_packets` (generated - queue-dropped -
  still queued - delivered), which isolates air losses.
* Energy per delivered bit, split into a TX term and an RX term:
  TX events are actual PHY transmissions per modem (MAC tx counters), RX
  events are MAC rx counters.  Powers are explicit hardware assumptions
  (see ENERGY_POWER_W), NOT simulated quantities: recalibrate against
  real modems before quoting absolute numbers.  The acoustic side uses a
  faster assumption than before TX=20 W while the optical side keeps the
  YAML TxPower of 10 W.

Known simulator bug (data-quality flag)
---------------------------------------
`hdr_uwcbr::sn_` is a uint16_t and `Module/UW/CBR` ships with
`drop_out_of_order_ 1`.  When a run generates more than 65535 packets, the
sequence number wraps and the sink's expected-sequence latch never
recovers: every later arrival is dropped as out-of-sequence, so
`getrecvpkts` (and the goodput/delay derived from it) is censored from
that point on.  This was verified by instrumenting uwcbr (0 duplicate and
6639 out-of-sequence drops after the wrap in a saturated acoustic run).
The destination modem's own reception counter is correct, and equals the
application count exactly below the wrap, so the runner reports it as
`delivered_packets` and sets `app_counter_censored`; the affected
offered-load points (mean period <= 0.01 s) must be read through the
network counters, not through `pdr_app`.

Repetitions consume consecutive RNG substreams (one per repetition, shared
seeds across technologies for paired statistics), and each run is
checkpointed to ``results.csv`` as it completes: a crash never loses
finished configurations.

Usage
-----
  python3 run_comparison_v2.py                 # full grid (30 reps)
  python3 run_comparison_v2.py --sweeps distance,packet_size
  python3 run_comparison_v2.py --quick         # 1 rep, 20 s stop time

All simulations are launched from this script's directory so the relative
LUT paths of the beam mode resolve correctly.
"""

import argparse
import concurrent.futures
import math
import os
import re
import shlex
import statistics
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[6]
ENV_PATH = REPO_ROOT / "DESERT_buildCopy_LOCAL" / "environment"
OPTICAL_V2 = SCRIPT_DIR / "multi_hop_optical_v2.tcl"
ACOUSTIC_V2 = SCRIPT_DIR / "single_link_acoustic_v2.tcl"

TECHNOLOGIES = ("acoustic", "optical", "beam_optical")

# ------------------------------------------------------------------ #
# Traffic defaults shared by every technology (fair comparison).      #
# ------------------------------------------------------------------ #
BASE = {
    "cbr_period": 0.25,          # s, mean inter-packet time (Poisson)
    "packet_size": 125,          # bytes of application payload
    "depth": -10.0,              # m, shared modem depth
    "start_time": 0.1,           # s, CBR start time (both v2 Tcl scripts)
    "stop_time": 1000.0,         # s, CBR stop time
    "poisson_traffic": 1,        # Poisson inter-arrivals on every sweep
    "attenuation_scale": 1.0,    # scalar for the analytic c = 0.3/scale
    "optical_txpower": 10.0,     # W
    "optical_threshold": 15.0,   # dB
    "optical_theta": 0.524,      # rad
}

# ------------------------------------------------------------------ #
# Analytical energy model.  Powers are hardware assumptions, not      #
# simulation outputs; the optical TX power matches the configured TM, #
# the others are typical-power placeholders to calibrate.  Bit rates  #
# are the configured PHY rates of the two Tcl scripts.                #
# ------------------------------------------------------------------ #
ENERGY_POWER_W = {
    "acoustic": {"tx": 20.0, "rx": 4.0},
    "optical": {"tx": 10.0, "rx": 1.5},
    "beam_optical": {"tx": 10.0, "rx": 1.5},
}
PHY_BITRATE_BPS = {"acoustic": 20768.0, "optical": 1.0e6,
                   "beam_optical": 1.0e6}

# ------------------------------------------------------------------ #
# Output parsing (machine-readable block from the v2 Tcl scripts).    #
# ------------------------------------------------------------------ #
SENT_RE = re.compile(r"^sent_packets:\s*([0-9]+)$", re.MULTILINE)
RECEIVED_RE = re.compile(r"^received_packets:\s*([0-9]+)$", re.MULTILINE)
FTT_RE = re.compile(r"^ftt_mean_s:\s*([-+0-9.eE]+)$", re.MULTILINE)
FTT_STD_RE = re.compile(r"^ftt_std_s:\s*([-+0-9.eE]+)$", re.MULTILINE)
CBR_THR_RE = re.compile(r"^cbr_thr_bps:\s*([-+0-9.eE]+)$", re.MULTILINE)
NODE_RE = re.compile(
    r"^\s*node (\d+): mac_tx=(\d+)\s+"
    r"mac_rx=(\d+)\s+up_rx=(\d+)\s+q_final=([0-9]+)\s*$", re.MULTILINE)


def build_args(technology: str, case: dict) -> list:
    """Command-line argument list for the matching v2 Tcl script."""
    if technology == "acoustic":
        return [
            case["n_relays"],            # accepted (ignored) for symmetry
            case["cbr_period"],
            case["packet_size"],
            case["total_distance"],
            case["depth"],
            case["stop_time"],
            case["rngstream"],
            case["poisson_traffic"],
        ]
    is_beam = 1 if technology == "beam_optical" else 0
    # One modem per relay: hop_length = total / hop_count exactly, and
    # hop_count = n_relays + 1 as in the receiver's sim metrics block.
    hop_count = case["n_relays"] + 1
    return [
        case["n_relays"],
        case["cbr_period"],
        case["packet_size"],
        case["total_distance"] / hop_count,
        case["depth"],
        case["stop_time"],
        case["rngstream"],
        case["poisson_traffic"],
        case["attenuation_scale"],
        case["optical_txpower"],
        case["optical_threshold"],
        case["optical_theta"],
        is_beam,
    ]


def run_case(technology: str, case: dict, log_path: Path) -> dict:
    """Launch one ns run and turn its metrics block into a result row."""
    sim_path = OPTICAL_V2 if technology != "acoustic" else ACOUSTIC_V2
    args = build_args(technology, case)
    command = "source {env} && ns {sim} {args}".format(
        env=shlex.quote(str(ENV_PATH.resolve())),
        sim=shlex.quote(str(sim_path.resolve())),
        args=" ".join(shlex.quote(str(a)) for a in args),
    )
    completed = subprocess.run(
        ["zsh", "-lc", command], cwd=SCRIPT_DIR, text=True,
        capture_output=True, check=False,
    )
    output = completed.stdout + completed.stderr
    log_path.write_text(output, encoding="utf-8")
    if completed.returncode != 0:
        raise RuntimeError(f"ns exited with {completed.returncode}.")

    match = lambda regex: (lambda m: float(m.group(1)) if m else math.nan)(
        regex.search(output))
    sent = match(SENT_RE)
    received = match(RECEIVED_RE)
    if math.isnan(sent) or math.isnan(received):
        raise RuntimeError("metrics block missing from the ns output.")

    hop_count = case["n_relays"] + 1 if technology != "acoustic" else 1
    nodes = [(int(n), int(tx), int(rx), int(up), int(q))
             for n, tx, rx, up, q in NODE_RE.findall(output)]
    tx_by_node = {n: (tx, rx, up, q) for n, tx, rx, up, q in nodes}

    # Edge h goes modem h -> modem h+1.  TDMA mac_rx counts only packets
    # whose destination is this modem, so the ratio is the edge PDR.
    # Downstream edges of a stalled chain never transmit; their PDR stays
    # undefined and is excluded from mean/weak aggregation.
    edge_pdrs = []
    for edge in range(hop_count):
        tx_n = tx_by_node.get(edge, (0, 0, 0, 0))[0]
        rx_n = tx_by_node.get(edge + 1, (0, 0, 0, 0))[1]
        edge_pdrs.append(rx_n / tx_n if tx_n else math.nan)
    finite_edges = [v for v in edge_pdrs if math.isfinite(v)]

    # Delivered-to-destination count.  `received_packets` is the CBR
    # application counter, which DESERT CENSORS after 65536 generated
    # packets: hdr_uwcbr::sn_ is a uint16_t, and the sink keeps
    # drop_out_of_order_ enabled by default, so after the sequence number
    # wraps every arriving packet is classified as out-of-sequence and
    # discarded (verified by instrumenting uwcbr: exactly 0 duplicate and
    # 6639 out-of-sequence drops after the wrap).  The MAC reception
    # counter of the sink modem is unaffected by that bug, and equals the
    # application count exactly whenever the app counter is not censored
    # (checked against UDP receipts in the traces).  It is therefore the
    # primary "delivered" count; the raw app counter is kept as
    # `received_packets` / `pdr_app` and the censoring is flagged.
    sink_mac_rx = tx_by_node.get(hop_count, (0, 0, 0, 0))[1]
    censored = sent > 65535
    delivered = sink_mac_rx

    # Power is NOT simulated (see module docstring): TX energy counts
    # actual PHY transmissions per node; RX energy counts delivered
    # receptions per node.  On-air duration uses the payload size, ignoring
    # MAC/PHY header bytes for both technologies alike.
    bitrate = PHY_BITRATE_BPS[technology]
    packet_time = case["packet_size"] * 8.0 / bitrate
    power = ENERGY_POWER_W[technology]
    tx_events = sum(tx for _, (tx, _, _, _) in tx_by_node.items())
    rx_events = sum(rx for _, (_, rx, _, _) in tx_by_node.items())
    delivered_bits = delivered * case["packet_size"] * 8.0
    tx_energy_j = tx_events * power["tx"] * packet_time
    rx_energy_j = rx_events * power["rx"] * packet_time

    # Queue drop accounting: every packet admitted by the IP layer either
    # leaves through the radio (mac_tx), still sits in the queue
    # (q_final), or was dropped.  The sink has no MAC-queue drops to
    # attribute, so it is excluded.
    queue_drops = 0
    total_q_final = 0
    for node_id, (_, _, up, q) in tx_by_node.items():
        total_q_final += q
        if node_id != hop_count:  # sink node index == hop_count
            queue_drops += max(0, up - tx_by_node[node_id][0] - q)

    # Anything generated at the source that is neither queue-dropped, nor
    # still queued, nor delivered to the destination modem was lost on the
    # air (attenuation / PHY errors) or is still in flight at stop time.
    phy_lost = sent - delivered - queue_drops - total_q_final

    return {
        "technology": technology,
        "n_relays": case["n_relays"],
        "hop_count": hop_count,
        "total_distance": case["total_distance"],
        "hop_length": (case["total_distance"] / hop_count
                       if technology != "acoustic" else case["total_distance"]),
        "cbr_period": case["cbr_period"],
        "packet_size": case["packet_size"],
        "poisson_traffic": case["poisson_traffic"],
        "attenuation_scale": case["attenuation_scale"],
        "sent_packets": sent,
        "delivered_packets": delivered,
        "received_packets": received,
        "app_counter_censored": censored,
        "pdr": delivered / sent if sent else math.nan,
        "pdr_app": received / sent if sent else math.nan,
        "goodput_bps": (delivered_bits
                        / max(1e-9, case["stop_time"] - case["start_time"])),
        "cbr_thr_bps": match(CBR_THR_RE),
        "delay_mean_s": match(FTT_RE),
        "delay_std_s": match(FTT_STD_RE),
        "mean_edge_pdr": statistics.mean(finite_edges)
            if finite_edges else math.nan,
        "weakest_edge_pdr": (min(finite_edges)
                             if finite_edges else math.nan),
        "edge_pdrs": "|".join(f"{v:.4f}" for v in edge_pdrs),
        "tx_events": tx_events,
        "rx_events": rx_events,
        "queue_drops_total": queue_drops,
        "queue_final_total": total_q_final,
        "phy_lost_packets": phy_lost,
        "tx_energy_per_bit_uj": (tx_energy_j / delivered_bits * 1e6
                                 if delivered_bits > 0 else math.nan),
        "rx_energy_per_bit_uj": (rx_energy_j / delivered_bits * 1e6
                                 if delivered_bits > 0 else math.nan),
        "energy_per_bit_uj": ((tx_energy_j + rx_energy_j) / delivered_bits * 1e6
                              if delivered_bits > 0 else math.nan),
        "packet_time_s": packet_time,
    }


def execute_case(idx_case, log_dir: Path):
    idx, case = idx_case
    technology = str(case["technology"])
    log_path = log_dir / (
        f"{idx:05d}_{technology}_{case['sweep']}_{case['sweep_value']:g}"
        f"_rep{case['rngstream']:02d}.log"
    )
    base = {k: case[k] for k in (
        "n_relays", "total_distance", "cbr_period", "packet_size", "depth",
        "stop_time", "rngstream", "poisson_traffic", "attenuation_scale",
        "optical_txpower", "optical_threshold", "optical_theta")}
    try:
        result = run_case(technology, case, log_path)
    except (RuntimeError, KeyError, ValueError) as exc:
        print(f"run {idx} failed ({exc}); recorded as failed: {log_path}")
        result = dict(base)
        result["technology"] = technology
        result["failed"] = True
        result["error"] = str(exc)
        return idx, result
    result["failed"] = False
    result.update({"sweep": case["sweep"], "sweep_value": case["sweep_value"],
                   "rngstream": case["rngstream"]})
    return idx, result


# ------------------------------------------------------------------ #
# Sweep definitions.  Every sweep keeps the acoustic baseline and the #
# two optical hardware variants on identical CBR traffic and timing.  #
# The acoustic link spans total_distance directly; the optical chain  #
# spreads (n_relays + 1) equal hops over the same total distance.     #
# ------------------------------------------------------------------ #
def build_cases(repetitions: int, stop_time: float | None) -> list:
    cases = []

    def add(sweep, value, n_relays, total_distance, **overrides):
        case = dict(BASE)
        if stop_time is not None:
            case["stop_time"] = stop_time
        case.update({"n_relays": n_relays, "total_distance": total_distance})
        case.update(overrides)
        for technology in TECHNOLOGIES:
            for repetition in range(1, repetitions + 1):
                c = dict(case)
                c.update({"sweep": sweep, "sweep_value": float(value),
                          "technology": technology,
                          "rngstream": repetition})
                cases.append(c)

    # 1. Source-destination distance with a fixed two-relay chain.  The
    #    range is extended to 1600 m to sample the acoustic graded-loss
    #    knee (~1.35-1.6 km with the 0 dB acquisition threshold, see
    #    single_link_acoustic_v2.tcl); both optical variants saturate at
    #    their per-hop reach long before that.
    for d in (20.0, 40.0, 60.0, 80.0, 100.0, 200.0, 500.0, 1000.0,
              1200.0, 1300.0, 1400.0, 1500.0, 1600.0):
        add("distance", d, 2, d)

    # 2. Relay count at a fixed 100 m target so hop lengths shrink as the
    #    chain grows: the classic multi-hop trade-off.
    for nr in (1, 2, 3, 4, 5):
        add("relay_count_fixed_100m", nr, nr, 100.0)

    # 3. Offered load, Poisson inter-arrivals, two relays, 50 m total.
    for p in (0.005, 0.01, 0.02, 0.05, 0.1, 0.25, 0.5, 1.0):
        add("offered_load", p, 2, 50.0, cbr_period=p)

    # 4. Payload size, two relays, 50 m total.
    for size in (64, 125, 250, 500):
        add("packet_size", size, 2, 50.0, packet_size=size)

    # 5. Water turbidity: analytic c = 0.3 x scale, equal for the ordinary
    #    and the beam-LUT optical variant (same propagation object).  The
    #    acoustic baseline is turbidity-invariant and just acts as reference.
    for c in (0.1, 0.3, 0.5, 0.8, 1.2, 1.6, 2.0):
        add("turbidity", c, 2, 50.0, attenuation_scale=c / 0.3)
    return cases


# ------------------------------------------------------------------ #
# Summary statistics with 95% Student's t confidence intervals.       #
# ------------------------------------------------------------------ #
T_CRIT_95 = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571, 6: 2.447,
             7: 2.365, 8: 2.306, 9: 2.262, 10: 2.228, 11: 2.201, 12: 2.179,
             13: 2.160, 14: 2.145, 15: 2.131, 16: 2.120, 17: 2.110,
             18: 2.101, 19: 2.093, 20: 2.086, 21: 2.080, 22: 2.074,
             23: 2.069, 24: 2.064, 25: 2.060, 26: 2.056, 27: 2.052,
             28: 2.048, 29: 2.045, 30: 2.042, 40: 2.021, 50: 2.009,
             60: 2.000, 100: 1.984}


def t_crit_95(df: int) -> float:
    if df in T_CRIT_95:
        return T_CRIT_95[df]
    if df <= 1:
        return 12.706
    if df >= 100:
        return 1.96
    keys = sorted(T_CRIT_95)
    for k0, k1 in zip(keys, keys[1:]):
        if k0 <= df <= k1:
            f = (df - k0) / (k1 - k0)
            return T_CRIT_95[k0] * (1 - f) + T_CRIT_95[k1] * f
    return 1.96


def ci95(series: pd.Series) -> float:
    s = series.dropna()
    n = len(s)
    if n <= 1:
        return 0.0
    std = s.std(ddof=1)
    if math.isnan(std) or std == 0:
        return 0.0
    return t_crit_95(n - 1) * std / math.sqrt(n)


METRICS = ["pdr", "pdr_app", "goodput_bps", "delay_mean_s", "mean_edge_pdr",
           "weakest_edge_pdr", "queue_drops_total", "queue_final_total",
           "phy_lost_packets", "energy_per_bit_uj",
           "tx_energy_per_bit_uj", "rx_energy_per_bit_uj"]

SWEEP_LABELS = {
    "distance": "Source-destination distance (m)",
    "relay_count_fixed_100m": "Relays spanning a fixed 100 m link",
    "offered_load": "Poisson CBR mean period (s)",
    "packet_size": "Application payload (bytes)",
    "turbidity": "Attenuation coefficient c (1/m)",
}
TECH_COLORS = {"acoustic": "tab:orange", "optical": "tab:blue",
               "beam_optical": "tab:green"}
TECH_LABELS = {"acoustic": "Direct acoustic", "optical": "Optical chain",
               "beam_optical": "Optical chain + beam LUT"}
TECH_STYLES = {"acoustic": ("s", "--"), "optical": ("o", "-"),
               "beam_optical": ("^", "-.")}


def plot_sweep(df_summary: pd.DataFrame, sweep: str, out_dir: Path,
               optical_only_last_panel: bool = True) -> None:
    """1x5 panel figure per sweep with 95% CI error bars."""
    selected = df_summary[df_summary["sweep"] == sweep].copy()
    if selected.empty:
        return
    vals = np.sort(selected["sweep_value"].unique().astype(float))
    span = vals[-1] - vals[0] if len(vals) > 1 else 1.0
    log_x = len(vals) > 1 and vals.min() > 0 and vals.max() / vals.min() >= 50
    dodge = {"acoustic": -0.012 * span, "optical": 0.0,
             "beam_optical": +0.012 * span}
    rx_dodge = {"acoustic": 0.94, "optical": 1.0, "beam_optical": 1.06}

    fig, axes = plt.subplots(1, 5, figsize=(27, 4.8), dpi=120)
    panel_y = [[] for _ in range(5)]

    for technology in TECHNOLOGIES:
        pts = (selected[selected["technology"] == technology]
               .sort_values("sweep_value"))
        if pts.empty:
            continue
        raw_x = pts["sweep_value"].astype(float).values
        x = (raw_x * rx_dodge[technology] if log_x
             else raw_x + dodge[technology])
        mk, ls = TECH_STYLES[technology]
        err_kwargs = dict(fmt=mk + ls, color=TECH_COLORS[technology],
                          label=TECH_LABELS[technology], linewidth=1.6,
                          markersize=5, capsize=4, barsabove=True)

        y = 100 * pts["pdr_mean"].values
        axes[0].errorbar(x, y, yerr=100 * pts["pdr_ci95"].values,
                         **err_kwargs)
        panel_y[0].extend(y)

        y = pts["goodput_bps_mean"].values
        axes[1].errorbar(x, y, yerr=pts["goodput_bps_ci95"].values,
                         **err_kwargs)
        panel_y[1].extend(y)

        ok = pts["pdr_mean"].values > 0
        y = 1000 * pts["delay_mean_s_mean"].values
        axes[2].errorbar(x[ok], y[ok], yerr=1000 * pts["delay_mean_s_ci95"].values[ok],
                         **err_kwargs)
        panel_y[2].extend(y[ok])

        ok = pts["energy_per_bit_uj_mean"].values > 0
        y = pts["energy_per_bit_uj_mean"].values
        axes[3].errorbar(x[ok], y[ok],
                         yerr=pts["energy_per_bit_uj_ci95"].values[ok],
                         **err_kwargs)
        panel_y[3].extend(y[ok])

        if optical_only_last_panel and technology != "acoustic":
            y = 100 * pts["weakest_edge_pdr_mean"].values
            axes[4].errorbar(x, y, yerr=100 * pts["weakest_edge_pdr_ci95"].values,
                             **err_kwargs)
            panel_y[4].extend(y)

    axes[0].set_ylabel("End-to-end PDR (%)")
    axes[0].set_ylim(-5, 105)
    axes[1].set_ylabel("Goodput over traffic window (bit/s)")
    axes[1].set_ylim(bottom=0)
    axes[2].set_ylabel("Mean delay (ms)")
    axes[3].set_ylabel("TX+RX energy per delivered bit (uJ/bit)")
    axes[4].set_ylabel("Weakest link-edge PDR (%)")
    if not optical_only_last_panel or not panel_y[4]:
        axes[4].set_visible(False)

    for ax, panel in zip(axes, panel_y):
        positive = [v for v in panel if v > 0]
        if positive and len(positive) > 1 and max(positive) / min(positive) >= 20:
            ax.set_yscale("log")
        ax.grid(True, linestyle=":", alpha=0.6, which="both")
        ax.set_xlabel(SWEEP_LABELS[sweep])
        ax.legend(frameon=True, fontsize=9)

    fig.suptitle(
        f"Acoustic direct vs. optical multi-hop (v2 design): {sweep}",
        fontsize=13, y=1.02)
    fig.tight_layout()
    save_path = out_dir / f"v2_{sweep}.png"
    fig.savefig(save_path, dpi=180, bbox_inches="tight")
    plt.close(fig)
    print(f"plot saved: {save_path}")


# ------------------------------------------------------------------ #
# Main experiment loop                                                #
# ------------------------------------------------------------------ #
def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run the v2 acoustic-vs-optical comparison sweeps.")
    parser.add_argument("--repetitions", type=int, default=30,
                        help="RNG substream repetitions per point (default 30)")
    parser.add_argument("--stop-time", type=float, default=None,
                       help="Override the CBR stop time (s)")
    parser.add_argument("--sweeps", type=str, default=None,
                        help="Comma-separated subset of sweeps to run")
    parser.add_argument("--quick", action="store_true",
                        help="Sanity smoke run: 1 repetition, 20 s stop time")
    parser.add_argument("--workers", type=int,
                        default=os.cpu_count() or 4)
    parser.add_argument("--out-dir", type=Path,
                    default=SCRIPT_DIR / "results")
    parser.add_argument("--no-plots", action="store_true")
    args = parser.parse_args()

    sweep_names = ([s.strip() for s in args.sweeps.split(",")]
                   if args.sweeps else list(SWEEP_LABELS))
    unknown = set(sweep_names) - set(SWEEP_LABELS)
    if unknown:
        parser.error(f"unknown sweep(s): {sorted(unknown)}")
    if args.quick:
        args.repetitions = 1
        args.stop_time = 20.0

    cases = [c for c in build_cases(args.repetitions, args.stop_time)
             if c["sweep"] in sweep_names]
    log_dir = args.out_dir / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    total = len(cases)
    print(f"{total} runs scheduled on {args.workers} workers "
          f"(repetitions={args.repetitions}, sweeps={sweep_names})")

    results = {}
    done = 0
    with concurrent.futures.ThreadPoolExecutor(
            max_workers=args.workers) as pool:
        futures = {pool.submit(execute_case, (i, item), log_dir): i
                   for i, item in enumerate(cases, 1)}
        for future in concurrent.futures.as_completed(futures):
            try:
                idx, row = future.result()
            except Exception as exc:  # keep the whole sweep alive
                idx, row = futures[future], {"failed": True, "error": str(exc)}
                print(f"run {idx} crashed in the executor: {exc}")
            results[idx] = row
            done += 1
            # Incremental checkpoint: nothing can lose finished runs.
            if done % 20 == 0 or done == total:
                pd.DataFrame([results[i] for i in sorted(results)]).to_csv(
                    args.out_dir / "results.csv", index=False)
            if done % 25 == 0 or done == total:
                print(f"progress: {done}/{total} ({100 * done / total:.1f}%)")

    df = pd.DataFrame([results[i] for i in sorted(results)])
    df.to_csv(args.out_dir / "results.csv", index=False)
    n_failed = int(df["failed"].sum()) if "failed" in df else 0
    print(f"runs finished: {len(df)} rows, {n_failed} failed runs "
          f"(details under {args.out_dir / 'logs'})")

    rows = df[df.get("failed", True) == False] if "failed" in df else df
    summary = (rows.groupby(["technology", "sweep", "sweep_value"])
               .agg({m: ["mean", "std", ("ci95", ci95)] for m in METRICS})
               .reset_index())
    summary.columns = [
        f"{c[0]}_{c[1]}".strip("_") if isinstance(c[1], str) and c[1]
        else c[0] for c in summary.columns
    ]
    counts = (rows.groupby(["technology", "sweep", "sweep_value"])
              ["rngstream"].count().reset_index(name="repetitions"))
    summary = counts.merge(summary, on=["technology", "sweep", "sweep_value"])
    summary = summary.fillna(0.0)
    summary.to_csv(args.out_dir / "summary.csv", index=False)
    print(f"summary: {args.out_dir / 'summary.csv'}")

    if not args.no_plots:
        for sweep in sweep_names:
            plot_sweep(summary, sweep, args.out_dir)


if __name__ == "__main__":
    main()