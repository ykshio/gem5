#!/usr/bin/env python3
"""Energy estimate for the L1 write-latency sweep (cachewrite workload).

Two interpretations of the user's spec are produced:
  (1) literal:   reads * Erd + writebacks * Ewr
                 where 'writebacks' = dirty evictions out of L1 (= 153 here)
                 -> heavily underestimates MRAM cost on L1-resident workloads.
  (2) array-writes: (ReadReq.hits + ReadReq.misses) * Erd
                  + (WriteReq.hits + WriteReq.misses) * Ewr
                 -> every demand access that touches the data array. This
                 is the physically meaningful count for MRAM L1 energy.

Parameter sources (see results/2026-05-23/energy/PARAMS.md):
  MRAM per-access (Erd, Ewr):
    derived from reference/nvmain/Config/custom/STTRAM_Everspin_16GB.config
    (tCAS=6, tCWD=10, tWP=14, tRCD=14, CLK=400MHz, IDD0=85mA, VDD=1.8V).
    Energy = current * VDD * cycles_per_access * t_clk.
    -> Erd ~= 25.872 nJ, Ewr ~= 97.020 nJ per 64-byte access.
  SRAM L1 baseline (Erd_SRAM, Ewr_SRAM):
    placeholder of 0.05 nJ/access (32nm 32KB L1, CACTI 7.0 class).
    For the final thesis, recompute with DESTINY using the same
    technology node (22nm) for both SRAM and MRAM so the ratio is
    apples-to-apples. Current value is a defensible upper bound for
    the SRAM case (literature is ~30-50 pJ at 32nm).
"""
import csv
import os
import re

ERD = 25.872   # nJ  (Everspin STT-MRAM per-access read; see PARAMS.md)
EWR = 97.020   # nJ  (Everspin STT-MRAM per-access write; see PARAMS.md)

# SRAM baseline (CACTI-class 32nm 32 KB L1; replace with DESTINY for thesis)
ERD_SRAM = 0.05  # nJ
EWR_SRAM = 0.05  # nJ

RUNS = [
    ("wlat_4_SRAM_baseline",   4,   "m5out/l1d_w4"),
    ("wlat_10_MRAM",          10,   "m5out/l1d_w10"),
    ("wlat_50_MRAM_slow",     50,   "m5out/l1d_w50"),
    ("wlat_100_MRAM_xtreme", 100,   "m5out/l1d_w100"),
]

def stat(path, key):
    pat = re.compile(rf"^{re.escape(key)}\s+(\S+)")
    with open(path) as f:
        for line in f:
            m = pat.match(line)
            if m:
                return m.group(1)
    return None

rows = []
for label, wlat, d in RUNS:
    f = os.path.join("/home/26kmc17/gem5", d, "stats.txt")
    sim_ticks = int(stat(f, "simTicks"))
    cpi       = float(stat(f, "system.cpu.cpi"))
    rd_h      = int(stat(f, "system.cpu.dcache.ReadReq.hits::total"))
    rd_m      = int(stat(f, "system.cpu.dcache.ReadReq.misses::total"))
    wr_h      = int(stat(f, "system.cpu.dcache.WriteReq.hits::total"))
    wr_m      = int(stat(f, "system.cpu.dcache.WriteReq.misses::total"))
    wb        = int(stat(f, "system.cpu.dcache.writebacks::total"))

    reads   = rd_h + rd_m
    writes  = wr_h + wr_m

    # Technology choice: wlat=4 is treated as SRAM, others as MRAM.
    if wlat == 4:
        erd, ewr, tech = ERD_SRAM, EWR_SRAM, "SRAM"
    else:
        erd, ewr, tech = ERD, EWR, "MRAM"

    # (1) literal formula
    e_lit_nj = reads * erd + wb * ewr
    # (2) array writes
    e_arr_nj = reads * erd + writes * ewr

    rows.append({
        "label": label,
        "tech": tech,
        "wlat_cyc": wlat,
        "simTicks_ns": sim_ticks,
        "CPI": cpi,
        "reads": reads,
        "writes": writes,
        "writebacks": wb,
        "E_literal_mJ": e_lit_nj / 1e6,
        "E_array_mJ":   e_arr_nj / 1e6,
        "E_total_arr_uJ": e_arr_nj / 1e3,
    })

out_csv = "/home/26kmc17/gem5/results/2026-05-23/energy/l1_wlat_energy.csv"
with open(out_csv, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    for r in rows:
        w.writerow(r)

print(f"[wrote] {out_csv}")
print()
hdr = f"{'config':28s} {'tech':>5s} {'wlat':>5s} {'CPI':>6s} {'reads':>8s} {'writes':>8s} {'wb':>5s} {'E_lit[mJ]':>10s} {'E_arr[mJ]':>10s}"
print(hdr)
print("-" * len(hdr))
for r in rows:
    print(f"{r['label']:28s} {r['tech']:>5s} {r['wlat_cyc']:5d} {r['CPI']:6.2f} "
          f"{r['reads']:8d} {r['writes']:8d} {r['writebacks']:5d} "
          f"{r['E_literal_mJ']:10.4f} {r['E_array_mJ']:10.4f}")

# Speed/energy product to visualize the tradeoff
print()
print("=== Time × Energy (lower is better) ===")
sram = rows[0]
for r in rows:
    t_ratio = r["simTicks_ns"] / sram["simTicks_ns"]
    e_ratio = r["E_array_mJ"]  / sram["E_array_mJ"]
    print(f"  {r['label']:28s}  time={t_ratio:5.3f}x  energy(arr)={e_ratio:5.3f}x")
