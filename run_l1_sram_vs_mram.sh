#!/bin/bash
# Round-2 H: L1 SRAM vs L1 MRAM head-to-head on cachewrite.
# Two configurations:
#   A: L1 SRAM (rlat=4,  wlat=4)
#   B: L1 MRAM (rlat=3,  wlat=10)  (Everspin-class L1, aggressive)
#
# Output: results/2026-05-23/l1_sram_vs_mram/{summary.csv, per-run stats}
set -e
cd /workspace/gem5

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
WORKLOAD=tests/test-progs/cachewrite/bin/riscv/linux/cachewrite
OUTROOT=results/2026-05-23/l1_sram_vs_mram
mkdir -p "$OUTROOT"

extract() {
    grep -E "^$2" "$1" | head -1 | awk '{print $2}'
}

run_cfg() {
    local label="$1" rlat="$2" wlat="$3"
    local outdir="$OUTROOT/${label}"
    rm -rf "$outdir"
    echo "[run] $label : L1D rlat=$rlat wlat=$wlat"
    $GEM5 --outdir="$outdir" $SCRIPT \
        --cmd="$WORKLOAD" \
        --l1d-read-latency="$rlat" \
        --l1d-write-latency="$wlat" 2>&1 | tail -3
    local f="$outdir/stats.txt"
    local sim=$(extract "$f" "simTicks")
    local cpi=$(extract "$f" "system\.cpu\.cpi")
    local rh=$(extract "$f" "system\.cpu\.dcache\.ReadReq\.hits::total")
    local rm=$(extract "$f" "system\.cpu\.dcache\.ReadReq\.misses::total")
    local wh=$(extract "$f" "system\.cpu\.dcache\.WriteReq\.hits::total")
    local wm=$(extract "$f" "system\.cpu\.dcache\.WriteReq\.misses::total")
    local wb=$(extract "$f" "system\.cpu\.dcache\.writebacks::total")
    local host=$(extract "$f" "hostSeconds")
    echo "$label,$rlat,$wlat,$sim,$cpi,$rh,$rm,$wh,$wm,$wb,$host" >> "$CSV"
}

CSV="$OUTROOT/summary.csv"
echo "config,l1d_rlat,l1d_wlat,simTicks,cpi,rd_hits,rd_miss,wr_hits,wr_miss,writebacks,host_s" > "$CSV"

run_cfg l1_sram_4_4   4  4
run_cfg l1_mram_3_10  3 10

echo
echo "=== summary.csv ==="
cat "$CSV"
