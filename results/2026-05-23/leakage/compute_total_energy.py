#!/usr/bin/env python3
"""Round-3 J: total energy (dynamic + leakage) for L3 across SRAM,
STT-MRAM, SOT-MRAM technologies using the F (WS=4MB) simulation
timing as the runtime budget.

Inputs:
  results/2026-05-23/ws4mb/sweep.csv (simTicks for each config)
  results/2026-05-23/leakage/PARAMS_leakage.md (P_leak values)

Outputs:
  results/2026-05-23/leakage/total_energy.csv
  results/2026-05-23/figures/total_energy_dyn_vs_leak.png

Tick model: gem5 default tick = 1 ps, so time_seconds = simTicks / 1e12.
"""
import csv
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# ------- L3 leakage power [W] @ 22nm 16MB (see PARAMS_leakage.md) -------
P_LEAK = {
    "SRAM": 5.00,
    "STT":  0.20,
    "SOT":  0.15,
}

# ------- per-access energy [nJ/64B access] (Everspin + CACTI placeholder) -------
ERD = {"SRAM": 0.05, "STT": 25.872, "SOT": 25.872}
EWR = {"SRAM": 0.05, "STT": 97.020, "SOT": 60.000}  # SOT-MRAM ~40% lower Ewr

# Round-2 F numbers (WS=4MB, rlat=10 for MRAM / 40 for SRAM, wlat=35/40)
RUNS = [
    # (label, tech, simTicks, l3_reads, l3_writebacks_in)
    ("SRAM 40/40",        "SRAM", 64528733000, 458804, 520613),
    ("STT-MRAM 10/35",    "STT",  48823803000, 458804, 520613),
    ("SOT-MRAM 10/35",    "SOT",  48823803000, 458804, 520613),
]

print(f"{'config':22s} {'time[ms]':>10s} {'E_dyn[mJ]':>10s} "
      f"{'E_leak[mJ]':>11s} {'E_total[mJ]':>11s}")
print("-" * 70)

rows = []
for label, tech, ticks, rd, wb in RUNS:
    time_s = ticks / 1e12
    e_dyn_nj = rd * ERD[tech] + wb * EWR[tech]
    e_leak_j = P_LEAK[tech] * time_s
    e_dyn_mj = e_dyn_nj / 1e6
    e_leak_mj = e_leak_j * 1e3
    e_total_mj = e_dyn_mj + e_leak_mj
    rows.append({
        "config": label,
        "tech":   tech,
        "time_ms": time_s * 1e3,
        "E_dyn_mJ": e_dyn_mj,
        "E_leak_mJ": e_leak_mj,
        "E_total_mJ": e_total_mj,
    })
    print(f"{label:22s} {time_s*1e3:10.3f} {e_dyn_mj:10.3f} "
          f"{e_leak_mj:11.3f} {e_total_mj:11.3f}")

# write CSV
out_csv = "/home/26kmc17/gem5/results/2026-05-23/leakage/total_energy.csv"
with open(out_csv, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    for r in rows:
        w.writerow(r)
print(f"\n[wrote] {out_csv}")

# verdict
sram = rows[0]
print()
print("=== Total energy ratio vs SRAM ===")
for r in rows[1:]:
    ratio = r["E_total_mJ"] / sram["E_total_mJ"]
    speed = sram["time_ms"] / r["time_ms"]
    print(f"  {r['config']:22s} total={ratio:5.3f}x  speed={speed:5.3f}x")

# stacked bar
fig, ax = plt.subplots(figsize=(7, 4.5))
labels = [r["config"] for r in rows]
dyn = [r["E_dyn_mJ"] for r in rows]
leak = [r["E_leak_mJ"] for r in rows]
xs = list(range(len(rows)))
ax.bar(xs, dyn,  color="#d62728", label="Dynamic", edgecolor="black")
ax.bar(xs, leak, bottom=dyn, color="#1f77b4", label="Leakage", edgecolor="black")
totals = [r["E_total_mJ"] for r in rows]
for i, t in enumerate(totals):
    ax.text(i, t + max(totals) * 0.02, f"{t:.1f} mJ",
            ha="center", fontsize=10, fontweight="bold")
ax.set_xticks(xs)
ax.set_xticklabels(labels, fontsize=10)
ax.set_ylabel("L3 energy on memstress WS=4MB [mJ]")
ax.set_title("Round-3 J: total L3 energy (dynamic + leakage)\n"
             "MRAM dynamic loss < SRAM leakage cost -> MRAM wins overall")
ax.legend(loc="upper right")
ax.grid(axis="y", alpha=0.3)
fig.tight_layout()

out_png = "/home/26kmc17/gem5/results/2026-05-23/figures/total_energy_dyn_vs_leak.png"
fig.savefig(out_png, dpi=150)
plt.close(fig)
print(f"[wrote] {out_png}")
