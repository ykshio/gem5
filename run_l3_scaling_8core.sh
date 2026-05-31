#!/bin/bash
# Task X6: does the 8-core shared-L3 capacity cliff (found in X4) get pushed
# back as L3 grows, and how do MRAM latencies change the picture?
#
# Fixed: 8 cores, multi-program memstress 4 MB x 4 per core => aggregate
# working set = 32 MB. Sweep the shared L3 capacity 16/32/64 MB at SRAM-class
# latency (40/40), then re-run L3=64 MB at MRAM-class latencies (SOT 10/22,
# STT 10/35) for the technology contrast.
#
#   WS=32MB vs L3=16MB -> WS = 2x L3  (cliff, from X4)
#   WS=32MB vs L3=32MB -> WS = 1x L3  (does it just fit?)
#   WS=32MB vs L3=64MB -> WS = 0.5x L3 (cliff should vanish)
#
# Run INSIDE the gem5-spec container (cd /workspace/gem5 assumed), e.g.
#   sudo docker run --rm --user $(id -u):$(id -g) \
#     -v /home/26kmc17/gem5:/workspace/gem5 \
#     gem5-spec bash -c "cd /workspace/gem5 && bash run_l3_scaling_8core.sh"
set -e
cd /workspace/gem5

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
MEMSTRESS=tests/test-progs/memstress/bin/riscv/linux/memstress
WL_OPTS="4 4"
NCPU=8

CSV=m5out/l3_scaling_8core_summary.csv
echo "config,technology,l3_size,l3_read_lat,l3_write_lat,simTicks,simSeconds,simInsts,l3_hits,l3_misses,l3_missRate,l3_wbDirtyHits,cpi_avg" > "$CSV"
printf "%-12s %-7s %-9s %-15s %-11s %-11s %-11s %-9s\n" \
    "config" "l3size" "rl/wl" "simTicks" "l3Hits" "l3Misses" "l3MissRate" "cpiAvg"

run_one () {
    local tag="$1" tech="$2" size="$3" rl="$4" wl="$5"
    local outdir="m5out/x6_${tag}"
    rm -rf "$outdir"
    $GEM5 --outdir="$outdir" $SCRIPT \
        --cmd="$MEMSTRESS" --options="$WL_OPTS" --num-cpus="$NCPU" \
        --l3-size="$size" --l3-read-latency="$rl" --l3-write-latency="$wl" \
        > /dev/null 2>&1
    local s="$outdir/stats.txt"
    local simTicks simInsts hits misses mrate wb cpiavg simSec
    simTicks=$(grep -E "^simTicks" "$s" | awk '{print $2}')
    simInsts=$(grep -E "^simInsts" "$s" | awk '{print $2}')
    # 1 tick = 1 ps (global freq 1e12 ticks/s) -> simSeconds = simTicks / 1e12
    simSec=$(awk -v t="$simTicks" 'BEGIN{printf "%.9f", t/1e12}')
    hits=$(  grep -E "^system\.l3\.overallHits::total"     "$s" | awk '{print $2}')
    misses=$(grep -E "^system\.l3\.overallMisses::total"   "$s" | awk '{print $2}')
    mrate=$( grep -E "^system\.l3\.overallMissRate::total" "$s" | awk '{print $2}')
    wb=$(    grep -E "^system\.l3\.WritebackDirty\.hits::total" "$s" | awk '{print $2}')
    cpiavg=$(grep -E "^system\.cpu[0-9]*\.cpi " "$s" | awk '{s+=$2; n++} END{if(n) printf "%.6f", s/n; else print "n/a"}')
    printf "%-12s %-7s %-9s %-15s %-11s %-11s %-11s %-9s\n" \
        "$tag" "$size" "${rl}/${wl}" "$simTicks" "${hits}" "${misses}" "${mrate}" "${cpiavg}"
    echo "${tag},${tech},${size},${rl},${wl},${simTicks},${simSec},${simInsts},${hits},${misses},${mrate},${wb},${cpiavg}" >> "$CSV"
}

echo "=== (1) SRAM-class latency (40/40), L3 capacity sweep ==="
run_one sram_16 sram 16MB 40 40
run_one sram_32 sram 32MB 40 40
run_one sram_64 sram 64MB 40 40

echo
echo "=== (2) MRAM-class latency at L3=64MB ==="
run_one sot_64  sotmram 64MB 10 22
run_one stt_64  sttmram 64MB 10 35

echo
echo "CSV: $CSV"
cat "$CSV"
echo
echo "Read it as: at 8 cores (WS=32MB), does miss-rate/CPI fall back to the"
echo "uncontended ~0.13 / ~23.5 as L3 grows 16->32->64 MB? And do MRAM rows at"
echo "64MB match SRAM-64 on miss-rate (capacity is identical) while differing"
echo "only via read latency (write stays hidden)?"
