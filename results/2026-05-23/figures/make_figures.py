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

# ----------- Figure 3b: full 4-point sweep with CPI + energy overlay -----
fig, ax1 = plt.subplots(figsize=(7, 4.5))
xs = list(range(len(wlat)))
labels_x = [f"{w}\n({t})" for w, t in zip(wlat, techs)]
bars = ax1.bar(xs, cpi, color=["#1f77b4" if t == "SRAM" else "#d62728" for t in techs],
               alpha=0.65, label="CPI")
ax1.set_xticks(xs)
ax1.set_xticklabels(labels_x)
ax1.set_xlabel("L1D write_latency [cycles] (technology)")
ax1.set_ylabel("CPI (bars)", color="#444")
for i, v in enumerate(cpi):
    ax1.text(i, v + 0.5, f"{v:.2f}", ha="center", fontsize=9, color="#333")
ax2 = ax1.twinx()
ax2.plot(xs, e_arr, color="#2ca02c", marker="o", linewidth=2,
         label="Energy (array writes)")
ax2.set_yscale("log")
ax2.set_ylabel("Total L1D energy [mJ] (log, line)", color="#2ca02c")
for i, v in enumerate(e_arr):
    ax2.annotate(f"{v:.4f}" if v < 0.1 else f"{v:.2f}",
                 (i, v), xytext=(8, -10), textcoords="offset points",
                 color="#2ca02c", fontsize=9)
fig.suptitle("L1D write_latency sweep — full 4 points\n"
             "(CPI grows 2.57x; energy stays constant within a technology)")
fig.tight_layout()
fig.savefig(os.path.join(OUT, "l1_wlat_energy_full.png"), dpi=150)
plt.close(fig)
print("[wrote] l1_wlat_energy_full.png")

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

# ----------- Figure 5: WS=4MB sweep (round 2 F) -----------
ws4_csv = "/home/26kmc17/gem5/results/2026-05-23/ws4mb/sweep.csv"
if os.path.exists(ws4_csv):
    rows4 = list(csv.DictReader(open(ws4_csv)))
    if rows4:
        labels = [f"{r['config']}\nrlat={r['l3_rlat']} wlat={r['l3_wlat']}\nbufs={r['l3_write_buffers']}"
                  for r in rows4]
        sim = [int(r["simTicks"]) / 1e9 for r in rows4]
        # color: buf=16 -> blue family, buf=4 -> red family
        cols = ["#1f77b4" if r["l3_write_buffers"] == "16" else "#d62728" for r in rows4]
        fig, ax = plt.subplots(figsize=(9, 4.5))
        ax.bar(range(len(rows4)), sim, color=cols)
        ax.set_xticks(range(len(rows4)))
        ax.set_xticklabels(labels, fontsize=8, rotation=15, ha="right")
        for i, s in enumerate(sim):
            ax.text(i, s, f"{s:.3f}", ha="center", va="bottom", fontsize=8)
        ax.set_ylabel("simTicks [s]")
        # Show L3 hit rate from miss rate
        hr_text = "\n".join([f"{r['config']}: miss_rate={r['l3_miss_rate']}" for r in rows4])
        ax.set_title("Round-2 F: WS=4MB (mixed L3 hit/miss)\n"
                     "blue=buffers=16, red=buffers=4")
        ax.grid(axis="y", alpha=0.3)
        fig.tight_layout()
        fig.savefig(os.path.join(OUT, "ws4mb_sweep.png"), dpi=150)
        plt.close(fig)
        print("[wrote] ws4mb_sweep.png")
else:
    print("[skip] ws4mb_sweep.png: ws4mb/sweep.csv not yet generated")

# ----------- Figure 6: rlat isolation (round 2 F-rlat) -----------
rlat_csv = "/home/26kmc17/gem5/results/2026-05-23/ws4mb/rlat.csv"
if os.path.exists(rlat_csv):
    rlat_rows = list(csv.DictReader(open(rlat_csv)))
    if rlat_rows:
        labels = [f"{r['config']}\nrlat={r['l3_rlat']}" for r in rlat_rows]
        sim = [int(r["simTicks"]) / 1e9 for r in rlat_rows]
        fig, ax = plt.subplots(figsize=(5, 4))
        ax.bar(range(len(rlat_rows)), sim, color=["#d62728", "#1f77b4"])
        ax.set_xticks(range(len(rlat_rows)))
        ax.set_xticklabels(labels, fontsize=9)
        for i, s in enumerate(sim):
            ax.text(i, s, f"{s:.3f} s", ha="center", va="bottom", fontsize=9)
        ax.set_ylabel("simTicks [s]")
        ax.set_title("F-rlat: L3 read_latency 10 vs 40 (WS=4MB, wlat=40)")
        ax.grid(axis="y", alpha=0.3)
        fig.tight_layout()
        fig.savefig(os.path.join(OUT, "rlat_effect.png"), dpi=150)
        plt.close(fig)
        print("[wrote] rlat_effect.png")
else:
    print("[skip] rlat_effect.png: rlat.csv not yet generated")

# ----------- Figure 7: L1 SRAM vs MRAM (round 2 H) -----------
h_csv = "/home/26kmc17/gem5/results/2026-05-23/l1_sram_vs_mram/summary.csv"
if os.path.exists(h_csv):
    h_rows = list(csv.DictReader(open(h_csv)))
    if h_rows:
        # Compute energy with the cited params
        ERD_MRAM, EWR_MRAM = 25.872, 97.020
        ERD_SRAM_, EWR_SRAM_ = 0.05, 0.05
        labels, cpis, energies, sims, techs2 = [], [], [], [], []
        for r in h_rows:
            wlat = int(r["l1d_wlat"])
            tech = "SRAM" if wlat <= 4 else "MRAM"
            erd, ewr = (ERD_SRAM_, EWR_SRAM_) if tech == "SRAM" else (ERD_MRAM, EWR_MRAM)
            rd = int(r["rd_hits"]) + int(r["rd_miss"])
            wr = int(r["wr_hits"]) + int(r["wr_miss"])
            e_nj = rd * erd + wr * ewr
            labels.append(f"{r['config']}\nrlat={r['l1d_rlat']} wlat={r['l1d_wlat']}")
            cpis.append(float(r["cpi"]))
            energies.append(e_nj / 1e6)  # to mJ
            sims.append(int(r["simTicks"]) / 1e9)
            techs2.append(tech)
        fig, axes = plt.subplots(1, 2, figsize=(9, 4))
        cols = ["#1f77b4" if t == "SRAM" else "#d62728" for t in techs2]
        axes[0].bar(range(len(h_rows)), cpis, color=cols)
        axes[0].set_xticks(range(len(h_rows)))
        axes[0].set_xticklabels(labels, fontsize=9)
        for i, v in enumerate(cpis):
            axes[0].text(i, v, f"{v:.2f}", ha="center", va="bottom")
        axes[0].set_ylabel("CPI")
        axes[0].set_title("Speed (lower better)")
        axes[0].grid(axis="y", alpha=0.3)
        axes[1].bar(range(len(h_rows)), energies, color=cols)
        axes[1].set_yscale("log")
        axes[1].set_xticks(range(len(h_rows)))
        axes[1].set_xticklabels(labels, fontsize=9)
        for i, v in enumerate(energies):
            axes[1].text(i, v, f"{v:.4g} mJ", ha="center", va="bottom")
        axes[1].set_ylabel("L1D energy [mJ] (log)")
        axes[1].set_title("Energy (lower better)")
        axes[1].grid(axis="y", alpha=0.3, which="both")
        fig.suptitle("Round-2 H: L1 SRAM vs MRAM head-to-head on cachewrite")
        fig.tight_layout()
        fig.savefig(os.path.join(OUT, "l1_sram_vs_mram.png"), dpi=150)
        plt.close(fig)
        print("[wrote] l1_sram_vs_mram.png")
else:
    print("[skip] l1_sram_vs_mram.png: summary.csv not yet generated")

# ----------- Figure 8: main memory DRAM vs MRAM (round 3 N) -----------
mm_csv = "/home/26kmc17/gem5/results/2026-05-23/main_mem/summary.csv"
if os.path.exists(mm_csv):
    mm_rows = list(csv.DictReader(open(mm_csv)))
    if mm_rows:
        # group by workload
        wls = sorted(set(r["workload"] for r in mm_rows))
        fig, axes = plt.subplots(1, 2, figsize=(10, 4))
        for ax, wl in zip(axes, wls):
            wl_rows = [r for r in mm_rows if r["workload"] == wl]
            labels_m = [f"{r['config']}\n{r['main_lat']}" for r in wl_rows]
            sims_m = [int(r["simTicks"]) / 1e9 for r in wl_rows]
            cols = ["#1f77b4", "#ff7f0e", "#d62728"]
            ax.bar(range(len(wl_rows)), sims_m, color=cols)
            for i, v in enumerate(sims_m):
                ax.text(i, v, f"{v:.2f} s", ha="center", va="bottom", fontsize=9)
            ax.set_xticks(range(len(wl_rows)))
            ax.set_xticklabels(labels_m, fontsize=8)
            ax.set_ylabel("simTicks [s]")
            ax.set_title(f"{wl}")
            ax.grid(axis="y", alpha=0.3)
        fig.suptitle("Round-3 N: main memory DRAM-proxy vs MRAM (preliminary,\n"
                     "SimpleMemory single-latency approximation; NVMain needed for full eval)")
        fig.tight_layout()
        fig.savefig(os.path.join(OUT, "main_mem_dram_vs_mram.png"), dpi=150)
        plt.close(fig)
        print("[wrote] main_mem_dram_vs_mram.png")
else:
    print("[skip] main_mem_dram_vs_mram.png: main_mem/summary.csv not yet generated")

print("\nFiles in", OUT)
for f in sorted(os.listdir(OUT)):
    print("  ", f)
