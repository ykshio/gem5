#!/bin/bash
# Round-3 N: preliminary main-memory technology swap using SimpleMemory.
# We compare three flat-latency configurations as proxies:
#   - dram_proxy    : SimpleMemory 100 ns  (DRAM-class average)
#   - mram_main_200 : SimpleMemory 200 ns  (MRAM Main, read=100/write=300 avg)
#   - mram_main_300 : SimpleMemory 300 ns  (MRAM Main slow, read=100/write=500 avg)
#
# Workloads: cachewrite (L1-resident) and memstress 4MB (mixed L3 hit/miss).
# Output: results/2026-05-23/main_mem/{summary.csv, per-run stats}
#
# Caveat: SimpleMemory has no read/write asymmetry and no DRAM channel
# structure. Treat results as a sensitivity sketch; redo with NVMain
# after 6/10.
set -e
cd /workspace/gem5

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
WL_CW=tests/test-progs/cachewrite/bin/riscv/linux/cachewrite
WL_MS=tests/test-progs/memstress/bin/riscv/linux/memstress
OUTROOT=results/2026-05-23/main_mem
mkdir -p "$OUTROOT"

extract() { grep -E "^$2" "$1" | head -1 | awk '{print $2}'; }

CSV="$OUTROOT/summary.csv"
echo "workload,config,main_lat,simTicks,cpi,l3_miss_lat,host_s" > "$CSV"

run_cfg() {
    local wl_label="$1" cmd="$2" options="$3" label="$4" main_lat="$5"
    local outdir="$OUTROOT/${wl_label}_${label}"
    rm -rf "$outdir"
    echo "[run] $wl_label/$label : main=$main_lat"
    $GEM5 --outdir="$outdir" $SCRIPT \
        --cmd="$cmd" \
        --options="$options" \
        --main-mem-type=simple \
        --main-latency="$main_lat" 2>&1 | tail -3
    local f="$outdir/stats.txt"
    local sim=$(extract "$f" "simTicks")
    local cpi=$(extract "$f" "system\.cpu\.cpi")
    local mlat=$(extract "$f" "system\.l3\.overallAvgMissLatency::total")
    local host=$(extract "$f" "hostSeconds")
    echo "$wl_label,$label,$main_lat,$sim,$cpi,$mlat,$host" >> "$CSV"
}

# cachewrite (L1-resident, minimal sensitivity to main memory)
run_cfg cachewrite "$WL_CW" ""  dram_proxy    100ns
run_cfg cachewrite "$WL_CW" ""  mram_main_200 200ns
run_cfg cachewrite "$WL_CW" ""  mram_main_300 300ns

# memstress WS=4MB (mixed L3 hit/miss, some traffic to main memory)
run_cfg memstress_4mb "$WL_MS" "4" dram_proxy    100ns
run_cfg memstress_4mb "$WL_MS" "4" mram_main_200 200ns
run_cfg memstress_4mb "$WL_MS" "4" mram_main_300 300ns

echo
echo "=== summary.csv ==="
cat "$CSV"
