#!/bin/bash
# Round-4 master: A (L2 MRAM) + B (WS sweep) + C (long-sim leakage scaling).
# Rebuilds memstress (now argv[2] = ITERS) then runs the three sweeps.
# Self-redirects all output to results/2026-05-23/round4.log so the
# Docker invocation can stay on a single line (no shell quoting risk).
set -e
cd /workspace/gem5
mkdir -p results/2026-05-23
exec > results/2026-05-23/round4.log 2>&1

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
WL_MS=tests/test-progs/memstress/bin/riscv/linux/memstress
OUTROOT=results/2026-05-23
extract() { grep -E "^$2" "$1" | head -1 | awk '{print $2}'; }

echo "============================================"
echo " Step 0: rebuild memstress (argv[2] = iters)"
echo "============================================"
bash build_memstress_riscv.sh

# ---------------------------------------------------------------
# A: L2 MRAM analysis (L1 SRAM fixed, L3 SRAM fixed, vary L2)
# ---------------------------------------------------------------
A_OUT="$OUTROOT/l2_mram"
mkdir -p "$A_OUT"
A_CSV="$A_OUT/sweep.csv"
echo "config,l2_rlat,l2_wlat,simTicks,cpi,l2_hits,l2_misses,l2_wb_in,host_s" > "$A_CSV"

run_l2() {
    local lbl="$1" rl="$2" wl="$3"
    local out="$A_OUT/$lbl"
    rm -rf "$out"
    echo "[A/run] $lbl : L2 rlat=$rl wlat=$wl"
    $GEM5 --outdir="$out" $SCRIPT \
        --cmd="$WL_MS" --options="4" \
        --l2-read-latency="$rl" --l2-write-latency="$wl" 2>&1 | tail -2
    f="$out/stats.txt"
    sim=$(extract "$f" "simTicks")
    cpi=$(extract "$f" "system\.cpu\.cpi")
    hits=$(extract "$f" "system\.l2\.overallHits::total")
    miss=$(extract "$f" "system\.l2\.overallMisses::total")
    wbin=$(extract "$f" "system\.l2\.WritebackDirty\.hits::total")
    host=$(extract "$f" "hostSeconds")
    echo "$lbl,$rl,$wl,$sim,$cpi,$hits,$miss,$wbin,$host" >> "$A_CSV"
}

echo "=== A: L2 MRAM sweep (memstress WS=4MB) ==="
run_l2 sram_14_14   14 14
run_l2 stt_7_25      7 25
run_l2 stt_7_35      7 35
run_l2 sot_7_18      7 18

# ---------------------------------------------------------------
# B: working-set sweep (L3 SRAM vs MRAM, multiple WS sizes)
# ---------------------------------------------------------------
B_OUT="$OUTROOT/ws_sweep"
mkdir -p "$B_OUT"
B_CSV="$B_OUT/sweep.csv"
echo "ws_mb,tech,l3_rlat,l3_wlat,simTicks,cpi,l3_hits,l3_misses,l3_miss_rate,l3_wb_in,host_s" > "$B_CSV"

run_ws() {
    local ws="$1" tech="$2" rl="$3" wl="$4"
    local out="$B_OUT/ws${ws}_${tech}"
    rm -rf "$out"
    echo "[B/run] WS=${ws}MB tech=$tech rlat=$rl wlat=$wl"
    $GEM5 --outdir="$out" $SCRIPT \
        --cmd="$WL_MS" --options="$ws" \
        --l3-read-latency="$rl" --l3-write-latency="$wl" 2>&1 | tail -2
    f="$out/stats.txt"
    sim=$(extract "$f" "simTicks")
    cpi=$(extract "$f" "system\.cpu\.cpi")
    hits=$(extract "$f" "system\.l3\.overallHits::total")
    miss=$(extract "$f" "system\.l3\.overallMisses::total")
    mr=$(extract "$f" "system\.l3\.overallMissRate::total")
    wbin=$(extract "$f" "system\.l3\.WritebackDirty\.hits::total")
    host=$(extract "$f" "hostSeconds")
    [ -z "$hits" ] && hits=0
    echo "$ws,$tech,$rl,$wl,$sim,$cpi,$hits,$miss,$mr,$wbin,$host" >> "$B_CSV"
}

echo "=== B: WS sweep ==="
for ws in 1 2 4 8 16 32 64; do
    run_ws "$ws" sram 40 40
    run_ws "$ws" stt  10 35
done

# ---------------------------------------------------------------
# C: long-sim leakage scaling (ITERS scaled up)
# ---------------------------------------------------------------
C_OUT="$OUTROOT/long_sim"
mkdir -p "$C_OUT"
C_CSV="$C_OUT/sweep.csv"
echo "tech,iters,simTicks,cpi,l3_hits,l3_miss,l3_wb_in,host_s" > "$C_CSV"

run_long() {
    local tech="$1" iters="$2" rl="$3" wl="$4"
    local out="$C_OUT/${tech}_iters${iters}"
    rm -rf "$out"
    echo "[C/run] tech=$tech iters=$iters"
    $GEM5 --outdir="$out" $SCRIPT \
        --cmd="$WL_MS" --options="4 $iters" \
        --l3-read-latency="$rl" --l3-write-latency="$wl" 2>&1 | tail -2
    f="$out/stats.txt"
    sim=$(extract "$f" "simTicks")
    cpi=$(extract "$f" "system\.cpu\.cpi")
    hits=$(extract "$f" "system\.l3\.overallHits::total")
    miss=$(extract "$f" "system\.l3\.overallMisses::total")
    wbin=$(extract "$f" "system\.l3\.WritebackDirty\.hits::total")
    host=$(extract "$f" "hostSeconds")
    echo "$tech,$iters,$sim,$cpi,$hits,$miss,$wbin,$host" >> "$C_CSV"
}

echo "=== C: long-sim leakage scaling (WS=4MB, ITERS up) ==="
for iters in 4 25 50; do
    run_long sram "$iters" 40 40
    run_long stt  "$iters" 10 35
done

echo
echo "=== A/sweep.csv ==="; cat "$A_CSV"
echo "=== B/sweep.csv ==="; cat "$B_CSV"
echo "=== C/sweep.csv ==="; cat "$C_CSV"
echo
echo "ALL DONE"
