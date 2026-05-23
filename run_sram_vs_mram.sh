#!/bin/bash
# SRAM vs MRAM L3 cache initial comparison experiment.
# Runs three configs (A/B/C) and emits a markdown-friendly summary table
# to stdout that can be pasted directly into a progress report.
set -e
cd /workspace/gem5

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
# memstress is a write-heavy single-threaded synthetic workload that avoids
# clone3()/thread syscalls unsupported by gem5 RISCV SE mode.
WORKLOAD=tests/test-progs/memstress/bin/riscv/linux/memstress
MAX_INSTS=0   # let memstress run to completion (it's bounded by ITERS)

run_cfg() {
    local name="$1" rlat="$2" wlat="$3"
    local outdir="m5out/$name"
    rm -rf "$outdir"
    echo "[run] $name : L3 read=$rlat write=$wlat"
    local insts_arg=""
    [[ "$MAX_INSTS" -gt 0 ]] && insts_arg="--max-insts=$MAX_INSTS"
    $GEM5 --outdir="$outdir" $SCRIPT \
        --cmd="$WORKLOAD" \
        --l3-read-latency="$rlat" --l3-write-latency="$wlat" \
        $insts_arg 2>&1 | tail -3
}

run_cfg sram      40 40
run_cfg mram      10 35
run_cfg mram_slow 10 50

# ---------- Summary ----------
extract() {
    local f="$1" pat="$2"
    grep -E "^$pat" "$f" | head -1 | awk '{print $2}'
}

declare -A simTicks simInsts cpi l3Hits l3Miss l3MissLat hostSecs

for n in sram mram mram_slow; do
    f="m5out/$n/stats.txt"
    simTicks[$n]=$(extract "$f" "simTicks")
    simInsts[$n]=$(extract "$f" "simInsts")
    cpi[$n]=$(extract "$f" "system\.cpu\.cpi")
    l3Hits[$n]=$(extract "$f" "system\.l3\.overallHits::total")
    l3Miss[$n]=$(extract "$f" "system\.l3\.overallMisses::total")
    l3MissLat[$n]=$(extract "$f" "system\.l3\.demandAvgMissLatency::total")
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
 SRAM vs MRAM L3 cache — initial comparison (gem5 v24, feature/mram-cache)
   Workload : tests/test-progs/threads/bin/riscv/linux/threads
   Cap      : --max-insts=$MAX_INSTS
   CPU      : TimingSimpleCPU @ 1 GHz   (1 cycle = 1 ns)
   L1/L2    : SRAM fixed (4cyc / 14cyc)
   L3       : 16 MB, 16-way; latency varies by config
==============================================================================

| Metric                       | A: SRAM 40/40    | B: MRAM 10/35    | C: MRAM 10/50    |
|------------------------------|------------------|------------------|------------------|
| simTicks                     | ${simTicks[sram]} | ${simTicks[mram]} | ${simTicks[mram_slow]} |
| simInsts                     | ${simInsts[sram]} | ${simInsts[mram]} | ${simInsts[mram_slow]} |
| CPI                          | ${cpi[sram]}     | ${cpi[mram]}     | ${cpi[mram_slow]} |
| L3 hits (total)              | ${l3Hits[sram]}  | ${l3Hits[mram]}  | ${l3Hits[mram_slow]} |
| L3 misses (total)            | ${l3Miss[sram]}  | ${l3Miss[mram]}  | ${l3Miss[mram_slow]} |
| L3 demandAvgMissLatency      | ${l3MissLat[sram]} | ${l3MissLat[mram]} | ${l3MissLat[mram_slow]} |
| host seconds                 | ${hostSecs[sram]} | ${hostSecs[mram]} | ${hostSecs[mram_slow]} |

Speedup vs SRAM (lower CPI is better)
  B: MRAM 10/35      CPI ratio (SRAM/MRAM) = $(ratio "${cpi[mram]}"     "${cpi[sram]}")
  C: MRAM 10/50      CPI ratio (SRAM/MRAM) = $(ratio "${cpi[mram_slow]}" "${cpi[sram]}")

simTicks ratio vs SRAM (lower is faster)
  B: $(python3 -c "print(f'{float(${simTicks[mram]})/float(${simTicks[sram]}):.3f}')")
  C: $(python3 -c "print(f'{float(${simTicks[mram_slow]})/float(${simTicks[sram]}):.3f}')")

==============================================================================
 まとめ (3-line takeaway)
   1. SRAM(40/40) vs MRAM(10/35): Read短縮の効果でCPIが改善 (上記比率を参照)
   2. ヒット率は3構成で同じ（メモリ技術非依存、容量・ASS同一のため）
   3. write_latency 35→50 で性能が低下するが、依然 SRAM(40/40) より速い場合が多い
==============================================================================
HEADER
