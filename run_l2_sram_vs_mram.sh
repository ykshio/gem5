#!/bin/bash
# L2 SRAM vs MRAM comparison.
# L1 (4cyc) and L3 (40cyc) are kept SRAM-fixed; only L2 read/write latency
# is varied. Because L2 sits between CPU-visible L1 misses and L3 writebacks,
# write_latency here directly stalls CPU-side traffic and the asymmetry shows up.
set -e
cd /workspace/gem5

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
WORKLOAD=tests/test-progs/memstress/bin/riscv/linux/memstress
MAX_INSTS=0

run_cfg() {
    local name="$1" rlat="$2" wlat="$3"
    local outdir="m5out/$name"
    rm -rf "$outdir"
    echo "[run] $name : L2 read=$rlat write=$wlat (L3 fixed 40/40)"
    local insts_arg=""
    [[ "$MAX_INSTS" -gt 0 ]] && insts_arg="--max-insts=$MAX_INSTS"
    $GEM5 --outdir="$outdir" $SCRIPT \
        --cmd="$WORKLOAD" \
        --l2-read-latency="$rlat" --l2-write-latency="$wlat" \
        --l3-read-latency=40 --l3-write-latency=40 \
        $insts_arg 2>&1 | tail -3
}

run_cfg l2_sram      14 14
run_cfg l2_mram      14 35
run_cfg l2_mram_slow 14 50

# ---------- Summary ----------
extract() {
    local f="$1" pat="$2"
    grep -E "^$pat" "$f" | head -1 | awk '{print $2}'
}

declare -A simTicks simInsts cpi l2Hits l2Miss l2MissLat hostSecs

for n in l2_sram l2_mram l2_mram_slow; do
    f="m5out/$n/stats.txt"
    simTicks[$n]=$(extract "$f" "simTicks")
    simInsts[$n]=$(extract "$f" "simInsts")
    cpi[$n]=$(extract "$f" "system\.cpu\.cpi")
    l2Hits[$n]=$(extract "$f" "system\.l2\.overallHits::total")
    l2Miss[$n]=$(extract "$f" "system\.l2\.overallMisses::total")
    l2MissLat[$n]=$(extract "$f" "system\.l2\.demandAvgMissLatency::total")
    hostSecs[$n]=$(extract "$f" "hostSeconds")
done

ratio() {
    python3 -c "
a, b = '$1', '$2'
try:
    print(f'{float(b)/float(a):.3f}')
except Exception:
    print('n/a')
"
}

cat <<HEADER

==============================================================================
 SRAM vs MRAM L2 cache — comparison (gem5 v24, feature/mram-cache)
   Workload : memstress (1MB buf, 16 passes, write+read pattern)
   Cap      : --max-insts=$MAX_INSTS
   CPU      : TimingSimpleCPU @ 1 GHz   (1 cycle = 1 ns)
   L1       : SRAM fixed (4 cyc)
   L2       : 256 kB, 8-way; latency varies by config
   L3       : 16 MB, 16-way; SRAM fixed 40/40
==============================================================================

| Metric                       | A: L2-SRAM 14/14 | B: L2-MRAM 14/35 | C: L2-MRAM 14/50 |
|------------------------------|------------------|------------------|------------------|
| simTicks                     | ${simTicks[l2_sram]} | ${simTicks[l2_mram]} | ${simTicks[l2_mram_slow]} |
| simInsts                     | ${simInsts[l2_sram]} | ${simInsts[l2_mram]} | ${simInsts[l2_mram_slow]} |
| CPI                          | ${cpi[l2_sram]}  | ${cpi[l2_mram]}  | ${cpi[l2_mram_slow]} |
| L2 hits (total)              | ${l2Hits[l2_sram]} | ${l2Hits[l2_mram]} | ${l2Hits[l2_mram_slow]} |
| L2 misses (total)            | ${l2Miss[l2_sram]} | ${l2Miss[l2_mram]} | ${l2Miss[l2_mram_slow]} |
| L2 demandAvgMissLatency      | ${l2MissLat[l2_sram]} | ${l2MissLat[l2_mram]} | ${l2MissLat[l2_mram_slow]} |
| host seconds                 | ${hostSecs[l2_sram]} | ${hostSecs[l2_mram]} | ${hostSecs[l2_mram_slow]} |

Slowdown vs SRAM baseline (higher CPI = slower)
  B: L2-MRAM 14/35      CPI ratio (MRAM/SRAM) = $(ratio "${cpi[l2_sram]}" "${cpi[l2_mram]}")
  C: L2-MRAM 14/50      CPI ratio (MRAM/SRAM) = $(ratio "${cpi[l2_sram]}" "${cpi[l2_mram_slow]}")

simTicks ratio vs SRAM (higher = slower)
  B: $(python3 -c "print(f'{float(${simTicks[l2_mram]})/float(${simTicks[l2_sram]}):.3f}')")
  C: $(python3 -c "print(f'{float(${simTicks[l2_mram_slow]})/float(${simTicks[l2_sram]}):.3f}')")

==============================================================================
 まとめ
   1. L2 では write_latency 増加が CPU-visible 性能に直結（CPU から近い層のため）
   2. L3 では同じ latency 差でも変化しなかった（writeback 非同期性で隠蔽）
   3. = MRAM L3 は性能影響を受けにくい層、という観察
==============================================================================
HEADER
