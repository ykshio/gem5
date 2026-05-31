#!/bin/bash
# Task X4: multi-core (CMP) basic data on the shared L3.
#
# Layout (--num-cpus>1): private L1I/L1D + private L2 per core, shared L3.
# Workload: multi-program -- each core runs its OWN independent copy of
# memstress with a 4 MB working set. With N cores the aggregate L3 footprint
# is N*4 MB, so beyond ~4 cores it exceeds the default 16 MB L3 and the cores
# start contending/evicting each other -> exactly the shared-L3 pressure the
# thesis is about.
#
# Run INSIDE the gem5-spec container (cd /workspace/gem5 assumed), e.g.
#   sudo docker run --rm --user $(id -u):$(id -g) \
#     -v /home/26kmc17/gem5:/workspace/gem5 \
#     gem5-spec bash -c "cd /workspace/gem5 && bash run_multicore_probe.sh"
set -e
cd /workspace/gem5

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
HELLO=tests/test-progs/hello/bin/riscv/linux/hello
MEMSTRESS=tests/test-progs/memstress/bin/riscv/linux/memstress
WL_OPTS="4 4"   # 4 MB buffer x 4 iterations, per core

echo "############################################"
echo "# Task X4 (smoke): 2-core hello"
echo "############################################"
rm -rf m5out/mc2_hello
if $GEM5 --outdir=m5out/mc2_hello $SCRIPT \
        --cmd="$HELLO" --num-cpus=2 2>&1 | tail -8; then
    echo "[2-core hello returned 0]"
else
    echo "[NG] 2-core hello FAILED"
fi

echo
echo "############################################"
echo "# Task X4: core-count sweep (memstress 4 MB x 4 per core)"
echo "#   L3 = 16 MB shared; aggregate footprint = N x 4 MB"
echo "############################################"
CSV=m5out/multicore_summary.csv
echo "num_cpus,simTicks,simInsts,l3_aggFootprintMB,l3_hits,l3_misses,l3_missRate,l3_wbDirtyHits,cpi_per_core" > "$CSV"
printf "%-9s %-15s %-14s %-10s %-11s %-11s %-12s %s\n" \
    "num_cpus" "simTicks" "simInsts" "l3Hits" "l3Misses" "l3MissRate" "l3WbDirty" "cpi_per_core"

for n in 1 2 4 8; do
    outdir="m5out/mc_${n}"
    rm -rf "$outdir"
    $GEM5 --outdir="$outdir" $SCRIPT \
        --cmd="$MEMSTRESS" --options="$WL_OPTS" --num-cpus="$n" \
        > /dev/null 2>&1
    s="$outdir/stats.txt"
    simTicks=$(grep -E "^simTicks"  "$s" | awk '{print $2}')
    simInsts=$(grep -E "^simInsts"  "$s" | awk '{print $2}')
    hits=$(  grep -E "^system\.l3\.overallHits::total"        "$s" | awk '{print $2}')
    misses=$(grep -E "^system\.l3\.overallMisses::total"      "$s" | awk '{print $2}')
    mrate=$( grep -E "^system\.l3\.overallMissRate::total"    "$s" | awk '{print $2}')
    wb=$(    grep -E "^system\.l3\.WritebackDirty\.hits::total" "$s" | awk '{print $2}')
    # Per-core CPI: single-core stat is system.cpu.cpi; multi-core is
    # system.cpu0.cpi, system.cpu1.cpi, ...  Collect whichever exists.
    cpis=$(grep -E "^system\.cpu[0-9]*\.cpi " "$s" | awk '{print $2}' | paste -sd'|' -)
    foot=$((n * 4))
    printf "%-9s %-15s %-14s %-10s %-11s %-11s %-12s %s\n" \
        "$n" "${simTicks:-n/a}" "${simInsts:-n/a}" "${hits:-n/a}" \
        "${misses:-n/a}" "${mrate:-n/a}" "${wb:-n/a}" "${cpis:-n/a}"
    echo "${n},${simTicks},${simInsts},${foot},${hits:-n/a},${misses:-n/a},${mrate:-n/a},${wb:-n/a},${cpis:-n/a}" >> "$CSV"
done

echo "############################################"
echo "CSV: $CSV"
echo "Expectation: as N rises, aggregate footprint (N*4MB) exceeds 16MB L3,"
echo "so l3 miss-rate climbs and per-core CPI degrades -> shared-L3 contention,"
echo "the regime where a large (MRAM) L3 pays off. simTicks = slowest core."
echo "############################################"
