#!/bin/bash
# Task X7: does the L3 write-latency hiding (X1, single-core O3) survive on an
# 8-core OoO CMP? Combines X1 (DerivO3CPU) + X4 (multi-core).
#
# 8 DerivO3CPU cores, multi-program memstress 4 MB x 4 (aggregate WS = 32 MB).
# L3 = 32 MB so the working set FITS (we want to isolate write-latency effects,
# not the capacity cliff). Sweep --l3-write-latency 4/10/50/100, read fixed 40.
# If simTicks stays flat, write hiding holds even on an OoO CMP.
#
# Run INSIDE the gem5-spec container (cd /workspace/gem5 assumed), e.g.
#   sudo docker run --rm --user $(id -u):$(id -g) \
#     -v /home/26kmc17/gem5:/workspace/gem5 \
#     gem5-spec bash -c "cd /workspace/gem5 && bash run_o3_multicore_writelat.sh"
set -e
cd /workspace/gem5

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
MEMSTRESS=tests/test-progs/memstress/bin/riscv/linux/memstress
WL_OPTS="4 4"
NCPU=8
L3SIZE=32MB   # fits the 8x4MB aggregate WS, so no capacity cliff

CSV=m5out/o3_mc_writelat_summary.csv
echo "l3_write_latency,simTicks,simInsts,l3_hits,l3_misses,l3_missRate,l3_wbDirtyHits,cpi_avg" > "$CSV"
printf "%-10s %-15s %-11s %-11s %-11s %-12s %-9s\n" \
    "wlat" "simTicks" "l3Hits" "l3Misses" "l3MissRate" "l3WbDirty" "cpiAvg"

for w in 4 10 50 100; do
    outdir="m5out/x7_o3mc_w${w}"
    rm -rf "$outdir"
    $GEM5 --outdir="$outdir" $SCRIPT \
        --cmd="$MEMSTRESS" --options="$WL_OPTS" \
        --cpu-type=DerivO3CPU --num-cpus="$NCPU" \
        --l3-size="$L3SIZE" --l3-read-latency=40 --l3-write-latency="$w" \
        > /dev/null 2>&1
    s="$outdir/stats.txt"
    simTicks=$(grep -E "^simTicks" "$s" | awk '{print $2}')
    simInsts=$(grep -E "^simInsts" "$s" | awk '{print $2}')
    hits=$(  grep -E "^system\.l3\.overallHits::total"     "$s" | awk '{print $2}')
    misses=$(grep -E "^system\.l3\.overallMisses::total"   "$s" | awk '{print $2}')
    mrate=$( grep -E "^system\.l3\.overallMissRate::total" "$s" | awk '{print $2}')
    wb=$(    grep -E "^system\.l3\.WritebackDirty\.hits::total" "$s" | awk '{print $2}')
    cpiavg=$(grep -E "^system\.cpu[0-9]*\.cpi " "$s" | awk '{s+=$2; n++} END{if(n) printf "%.6f", s/n; else print "n/a"}')
    printf "%-10s %-15s %-11s %-11s %-11s %-12s %-9s\n" \
        "$w" "$simTicks" "${hits}" "${misses}" "${mrate}" "${wb}" "${cpiavg}"
    echo "${w},${simTicks},${simInsts},${hits},${misses},${mrate},${wb},${cpiavg}" >> "$CSV"
done

echo "CSV: $CSV"
echo "simTicks flat across w=4..100 => write hiding holds on 8-core OoO too."
echo "simTicks rises => OoO CMP exposes L3 write latency (note for thesis)."
