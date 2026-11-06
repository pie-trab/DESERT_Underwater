#!/usr/bin/env python3
"""Post-run analysis of the full v2 comparison: consistency checks + compact
per-sweep result tables with 95% CI, ready to be pasted into the report."""
import math
from pathlib import Path

import pandas as pd

OUT = Path(__file__).resolve().parent / "results"
pd.set_option("display.width", 260)
pd.set_option("display.max_columns", 60)

df = pd.read_csv(f"{OUT}/results.csv")
s = pd.read_csv(f"{OUT}/summary.csv")

TECHS = ("acoustic", "optical", "beam_optical")
SWEEPS = ("distance", "relay_count_fixed_100m", "offered_load",
          "packet_size", "turbidity")

print("=== DATASET SHAPE ===")
print(f"result rows: {len(df)}, summary rows: {len(s)}")
print("failed rows:", int(df["failed"].sum()) if "failed" in df else 0)
print("repetitions per point:",
      s["repetitions"].min(), "..", s["repetitions"].max())
print("censored app-counter runs:",
      int(df["app_counter_censored"].sum()),
      "of", len(df))
cen = df[df["app_counter_censored"]][["technology", "sweep", "sweep_value"]]
print("censored points (sweep/value -> techs):")
if len(cen):
    for (sw, val), g in cen.groupby(["sweep", "sweep_value"]):
        print(f"  {sw}={val:g}: {sorted(g['technology'].unique())}")

print("\n=== CONSISTENCY CHECKS ===")
fails = 0


def check(name, ok):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'}  {name}")


check("pdr <= 1 everywhere", bool((df["pdr"] <= 1.0 + 1e-12).all()))
check("pdr_app <= 1 everywhere", bool((df["pdr_app"].dropna() <= 1.0 + 1e-12).all()))
check("weakest_edge_pdr <= 1 everywhere",
      bool(df["weakest_edge_pdr"].dropna().le(1.0 + 1e-12).all()))

# Conservation: generated = delivered + queue drops + residual queues + air loss
resid = (df["sent_packets"] - df["delivered_packets"] - df["queue_drops_total"]
         - df["queue_final_total"] - df["phy_lost_packets"])
check(f"packet conservation exact (max residual {resid.abs().max():.3g})",
      bool(resid.abs().max() < 1e-6))
check("phy_lost_packets >= 0", bool((df["phy_lost_packets"] >= -1e-9).all()))
check("queue drops <= sent - delivered",
      bool((df["queue_drops_total"] <= df["sent_packets"]
            - df["delivered_packets"] + 1e-9).all()))

# Energy identity
PT = {"acoustic": 125 * 8 / 20768.0, "optical": 125 * 8 / 1e6,
      "beam_optical": 125 * 8 / 1e6}
P = {"acoustic": (20.0, 4.0), "optical": (10.0, 1.5), "beam_optical": (10.0, 1.5)}
sub = df[(df["packet_size"] == 125) & df["energy_per_bit_uj"].notna()]
recomp = ((sub["tx_events"] * [P[t][0] for t in sub["technology"]]
           + sub["rx_events"] * [P[t][1] for t in sub["technology"]])
          * [PT[t] for t in sub["technology"]]
          / (sub["delivered_packets"] * 125 * 8) * 1e6)
err = (recomp - sub["energy_per_bit_uj"]).abs().max()
check(f"energy model re-check (max err {err:.2e} uJ/bit)", bool(err < 1e-6))

# Same RNG streams for the two optical variants
m = (df["sweep"] == "offered_load") & (df["sweep_value"] == 0.25)
piv = df[m].pivot_table(index="rngstream", columns="technology",
                        values="sent_packets")
check("optical/beam_optical identical per-rep traffic",
      bool((piv["optical"] == piv["beam_optical"]).all()))
# 30 Poisson draws of a count with std ~60 legitimately collide sometimes;
# independence is established by the substream-per-repetition design, and we
# only assert that no point degenerates to a handful of distinct draws.
nuniq = df.groupby(["technology", "sweep", "sweep_value"])["sent_packets"].nunique()
check(f"sent counts spread across repetitions (min {nuniq.min()} distinct/point)",
      bool(nuniq.min() >= 20))

# App vs delivered equal when the app counter is not censored
ok = df[~df["app_counter_censored"]]
check("app count == sink MAC count when not censored",
      bool((ok["received_packets"] == ok["delivered_packets"]).all()))

# goodput vs CBR throughput on an uncensored overhead-free point
chk = df[(df["cbr_period"] == 0.1) & (df["technology"] == "optical")
         & (~df["app_counter_censored"]) & (df["sweep"] == "offered_load")]
if len(chk):
    d = (chk["goodput_bps"] - chk["cbr_thr_bps"]).abs().max()
    print(f"info  goodput vs CBR throughput cross-check max diff: {d:.2f} bit/s")

print(f"\nchecks failing: {fails}")

print("\n=== RESULT TABLES (mean +/- 95% CI) ===")
for sweep in SWEEPS:
    sel = s[s["sweep"] == sweep].copy()
    if sel.empty:
        continue
    print(f"\n--- {sweep} ---")
    rows = []
    for val in sorted(sel["sweep_value"].unique()):
        for tech in TECHS:
            r = sel[(sel["technology"] == tech) & (sel["sweep_value"] == val)]
            if r.empty:
                continue
            x = r.iloc[0]
            rows.append({
                "value": val,
                "tech": tech,
                "pdr%": f"{100*x['pdr_mean']:.1f}±{100*x['pdr_ci95']:.1f}",
                "gput_kbps": f"{x['goodput_bps_mean']/1e3:.1f}",
                "delay_ms": f"{1e3*x['delay_mean_s_mean']:.0f}"
                             f"±{1e3*x['delay_mean_s_ci95']:.0f}",
                "E_uJ_bit": f"{x['energy_per_bit_uj_mean']:.1f}"
                            if x["energy_per_bit_uj_mean"] > 0 else "n/a",
                "weakest%": f"{100*x['weakest_edge_pdr_mean']:.0f}"
                            if not math.isnan(x["weakest_edge_pdr_mean"])
                            else "n/a",
                "qdrop": f"{x['queue_drops_total_mean']:.0f}",
                "phylost": f"{x['phy_lost_packets_mean']:.0f}",
                "app_cens": "yes" if (x["pdr_mean"] != x["pdr_app_mean"]) else "",
            })
    print(pd.DataFrame(rows).to_string(index=False))

print("\n=== HEADLINE DELIVERY vs DISTANCE (2 relays) ===")
sel = df[(df["sweep"] == "distance")]
for tech in TECHS:
    g = sel[sel["technology"] == tech].groupby("sweep_value")
    print(tech, {int(k): round(100 * v, 1) for k, v in g["pdr"].mean().items()})
