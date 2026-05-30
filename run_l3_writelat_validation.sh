#!/bin/bash
# Validation: prove that the L3 write_latency actually charges the data
# array on L3 write traffic (dirty writebacks from L2 into L3).
#
# Uses memstress with a 4 MB working set: 4 MB fits inside the 16 MB L3
# but far exceeds the 256 kB L2, so after warmup virtually all writeback
# traffic terminates in L3 write hits. Sweep the L3 write_latency from 4
# to 100 and confirm simTicks scales monotonically.
#
# Run INSIDE the gem5-spec container (cd /workspace/gem5 is assumed), e.g.
#   sudo docker run --rm --user $(id -u):$(id -g) \
#     -v /home/26kmc17/gem5:/workspace/gem5 \
#     gem5-spec bash -c "cd /workspace/gem5 && bash run_l3_writelat_validation.sh"
set -e
cd /workspace/gem5

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
WORKLOAD=tests/test-progs/memstress/bin/riscv/linux/memstress
# 4 MB buffer, 4 iterations: fits L3 (16 MB), exceeds L2 (256 kB).
WL_OPTS="4 4"

echo "============================================"
echo " L3 write_latency validation sweep"
echo " (workload: memstress, 4 MB buffer x 4 passes)"
echo "============================================"
printf "%-10s %-15s %-12s %-16s %-14s\n" \
    "wlat" "simTicks" "CPI" "l3WbDirtyHits" "l3Misses"

for w in 4 10 50 100; do
    outdir="m5out/l3_w${w}"
    rm -rf "$outdir"
    $GEM5 --outdir="$outdir" $SCRIPT \
        --cmd="$WORKLOAD" \
        --options="$WL_OPTS" \
        --l3-write-latency="$w" \
        2>&1 | tail -1 > /dev/null
    stats="$outdir/stats.txt"
    simTicks=$(grep -E "^simTicks"                              "$stats" | awk '{print $2}')
    cpi=$(     grep -E "^system\.cpu\.cpi"                      "$stats" | awk '{print $2}')
    # WritebackDirty hits == dirty lines written into L3 (the write traffic
    # that L3 write_latency is supposed to charge).
    l3wb=$(    grep -E "^system\.l3\.WritebackDirty\.hits::total" "$stats" | awk '{print $2}')
    l3miss=$(  grep -E "^system\.l3\.overallMisses::total"      "$stats" | awk '{print $2}')
    printf "%-10s %-15s %-12s %-16s %-14s\n" \
        "$w" "$simTicks" "$cpi" "${l3wb:-n/a}" "${l3miss:-n/a}"
done
echo "============================================"
echo "L3 write_latency is wired up correctly if simTicks rises monotonically."
echo "If simTicks is flat across w=4..100, the write_latency is not being"
echo "charged on L3 writeback traffic and needs implementation in the cache model."
