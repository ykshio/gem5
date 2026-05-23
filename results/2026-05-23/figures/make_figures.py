#!/usr/bin/env python3
"""Generate PNG figures for the weekly report / 6-10 presentation.
Inputs:
  results/2026-05-23/energy/l1_wlat_energy.csv
  results/2026-05-23/writeback_hiding/sweep.csv   (optional, may be absent)
"""
import csv
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

OUT = "/home/26kmc17/gem5/results/2026-05-23/figures"
os.makedirs(OUT, exist_ok=True)

# ----------- Figure 1: L1 wlat -> CPI -----------
energy_csv = "/home/26kmc17/gem5/results/2026-05-23/energy/l1_wlat_energy.csv"
rows = list(csv.DictReader(open(energy_csv)))
wlat = [int(r["wlat_cyc"]) for r in rows]
cpi  = [float(r["CPI"])    for r in rows]
sim  = [int(r["simTicks_ns"]) / 1e6 for r in rows]  # to ms
e_arr = [float(r["E_array_mJ"]) for r in rows]
techs = [r["tech"] for r in rows]

fig, ax = plt.subplots(figsize=(6, 4))
colors = ["#1f77b4" if t == "SRAM" else "#d62728" for t in techs]
ax.bar([str(w) for w in wlat], cpi, color=colors)
for i, v in enumerate(cpi):
    ax.text(i, v + 0.3, f"{v:.2f}", ha="center", fontsize=9)
ax.set_xlabel("L1D write_latency [cycles]")
ax.set_ylabel("CPI")
ax.set_title("L1D write_latency sweep: CPI on cachewrite\n(blue=SRAM baseline, red=MRAM)")
ax.grid(axis="y", alpha=0.3)
fig.tight_layout()
fig.savefig(os.path.join(OUT, "l1_wlat_cpi.png"), dpi=150)
plt.close(fig)
print("[wrote] l1_wlat_cpi.png")

# ----------- Figure 2: L1 wlat -> energy (log y) -----------
fig, ax = plt.subplots(figsize=(6, 4))
ax.bar([str(w) for w in wlat], e_arr, color=colors)
for i, v in enumerate(e_arr):
    ax.text(i, v * 1.3, f"{v:.4f} mJ", ha="center", fontsize=8)
ax.set_yscale("log")
ax.set_xlabel("L1D write_latency [cycles]")
ax.set_ylabel("Total L1D access energy [mJ] (log scale)")
ax.set_title("L1D access energy (Everspin params: Erd=25.872 nJ, Ewr=97.02 nJ)\n"
             "SRAM baseline uses Erd=Ewr=0.05 nJ (literature)")
ax.grid(axis="y", alpha=0.3, which="both")
fig.tight_layout()
fig.savefig(os.path.join(OUT, "l1_wlat_energy.png"), dpi=150)
plt.close(fig)
print("[wrote] l1_wlat_energy.png")

# ----------- Figure 3: Speed vs Energy scatter -----------
fig, ax = plt.subplots(figsize=(6, 4))
for w, c, e, t in zip(wlat, cpi, e_arr, techs):
    col = "#1f77b4" if t == "SRAM" else "#d62728"
    ax.scatter(c, e, s=80, c=col)
    ax.annotate(f"wlat={w}", (c, e), xytext=(5, 5), textcoords="offset points", fontsize=9)
ax.set_yscale("log")
ax.set_xlabel("CPI (lower is faster)")
ax.set_ylabel("Total L1D access energy [mJ] (log scale)")
ax.set_title("Speed vs energy trade-off on cachewrite\n(MRAM L1: slower AND ~1000x more energy)")
ax.grid(alpha=0.3, which="both")
fig.tight_layout()
fig.savefig(os.path.join(OUT, "l1_speed_energy.png"), dpi=150)
plt.close(fig)
print("[wrote] l1_speed_energy.png")

# ----------- Figure 4: writeback hiding table (if present) -----------
wb_csv = "/home/26kmc17/gem5/results/2026-05-23/writeback_hiding/sweep.csv"
if os.path.exists(wb_csv):
    wb_rows = list(csv.DictReader(open(wb_csv)))
    if wb_rows:
        # Build a {buffers}x{wlat} grid
        configs = [r["config"] for r in wb_rows]
        sim_ticks = [int(r["simTicks"]) for r in wb_rows]
        labels = [f"{r['config']}\nwlat={r['l3_wlat']} bufs={r['l3_write_buffers']}"
                  for r in wb_rows]
        fig, ax = plt.subplots(figsize=(8, 4))
        bars = ax.bar(range(len(wb_rows)), [s / 1e9 for s in sim_ticks])
        ax.set_xticks(range(len(wb_rows)))
        ax.set_xticklabels(labels, fontsize=8, rotation=20, ha="right")
        for i, s in enumerate(sim_ticks):
            ax.text(i, s/1e9, f"{s/1e9:.3f} s", ha="center", va="bottom", fontsize=8)
        ax.set_ylabel("simTicks [s]")
        ax.set_title("Writeback hiding refutation experiment\n"
                     "(memstress 32MB > L3 16MB; vary L3 wlat × write_buffers)")
        ax.grid(axis="y", alpha=0.3)
        fig.tight_layout()
        fig.savefig(os.path.join(OUT, "writeback_hiding.png"), dpi=150)
        plt.close(fig)
        print("[wrote] writeback_hiding.png")
else:
    print("[skip] writeback_hiding.png: sweep.csv not yet generated (run A-1/A-2 first)")

print("\nFiles in", OUT)
for f in sorted(os.listdir(OUT)):
    print("  ", f)
