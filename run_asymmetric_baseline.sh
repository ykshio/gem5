#!/bin/bash
# Task X3: re-confirm the Task A "L3 write hiding" finding under realistic
# asymmetric MRAM latencies (not just an abstract write sweep).
#
# Three technology points at L3 = 32 MB, threads workload:
#   SRAM : read=40 write=40  (symmetric, baseline)
#   SOT  : read=10 write=22  (fast read, moderate write)
#   STT  : read=10 write=35  (fast read, slow write)
# Then a "write-only" sweep at fixed read=10, write=22/35/60 to show the write
# latency itself does not move simTicks (read latency is what differentiates).
#
# Expectation: SOT and STT give ~identical simTicks (write hidden), both faster
# than SRAM (because read=10 << 40). The write sweep stays flat.
#
# Run INSIDE the gem5-spec container (cd /workspace/gem5 assumed), e.g.
#   sudo docker run --rm --user $(id -u):$(id -g) \
#     -v /home/26kmc17/gem5:/workspace/gem5 \
#     gem5-spec bash -c "cd /workspace/gem5 && bash run_asymmetric_baseline.sh"
set -e
cd /workspace/gem5

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
WORKLOAD=tests/test-progs/threads/bin/riscv/linux/threads
SIZE=32MB

CSV=m5out/asym_baseline_summary.csv
echo "config,l3_read_lat,l3_write_lat,simTicks,simInsts,cpi,l3_demandAvgMissLat,l3_hits,l3_misses,l3_wbDirtyHits" > "$CSV"

run_one () {
    local tag="$1" rl="$2" wl="$3"
    local outdir="m5out/asym_${tag}"
    rm -rf "$outdir"
    $GEM5 --outdir="$outdir" $SCRIPT \
        --cmd="$WORKLOAD" \
        --l3-size="$SIZE" \
        --l3-read-latency="$rl" \
        --l3-write-latency="$wl" \
        > /dev/null 2>&1
    local s="$outdir/stats.txt"
    local simTicks simInsts cpi avgml hits misses wb
    simTicks=$(grep -E "^simTicks"                                  "$s" | awk '{print $2}')
    simInsts=$(grep -E "^simInsts"                                  "$s" | awk '{print $2}')
    cpi=$(     grep -E "^system\.cpu\.cpi"                          "$s" | head -1 | awk '{print $2}')
    avgml=$(   grep -E "^system\.l3\.demandAvgMissLatency::total"   "$s" | awk '{print $2}')
    hits=$(    grep -E "^system\.l3\.demandHits::total"             "$s" | awk '{print $2}')
    misses=$(  grep -E "^system\.l3\.demandMisses::total"           "$s" | awk '{print $2}')
    wb=$(      grep -E "^system\.l3\.WritebackDirty\.hits::total"   "$s" | awk '{print $2}')
    printf "%-12s rl=%-3s wl=%-3s simTicks=%-15s cpi=%-10s wbDirty=%s\n" \
        "$tag" "$rl" "$wl" "$simTicks" "$cpi" "${wb:-n/a}"
    echo "${tag},${rl},${wl},${simTicks},${simInsts},${cpi:-n/a},${avgml:-n/a},${hits:-n/a},${misses:-n/a},${wb:-n/a}" >> "$CSV"
}

echo "=== Technology points (L3=$SIZE, threads) ==="
run_one SRAM 40 40
run_one SOT  10 22
run_one STT  10 35

echo
echo "=== Write-only sweep (read fixed=10, write 22/35/60) ==="
run_one wsweep_w22 10 22
run_one wsweep_w35 10 35
run_one wsweep_w60 10 60

echo
echo "CSV written to $CSV:"
cat "$CSV"
echo
echo "Interpretation:"
echo " - SOT vs STT simTicks ~equal  => L3 write latency hidden even with realistic asymmetry"
echo " - {SOT,STT} simTicks < SRAM   => benefit comes from the faster READ (10 vs 40)"
echo " - write sweep flat            => write latency alone does not move performance"
