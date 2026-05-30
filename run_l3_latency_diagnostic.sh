#!/bin/bash
# Diagnostic: distinguish "L3 write_latency is buggy" from "L3 write_latency
# is architecturally hidden under a blocking in-order CPU".
#
# Hypothesis: with TimingSimpleCPU (one outstanding access, blocking), a store
# completes when L1D accepts it. The dirty line's eventual writeback into L3
# happens asynchronously, so L3 *write* latency never sits on the CPU's
# critical path -> simTicks is flat vs --l3-write-latency. By contrast a load
# that misses L1D/L2 and hits L3 DOES block the CPU, so L3 *read* latency
# should move simTicks.
#
# If the READ sweep moves simTicks while the WRITE sweep stays flat, the cache
# model is correct and the flat write result is an architectural effect, not a
# bug. If BOTH are flat, L3 is not on the critical path at all (investigate).
#
# Run inside the gem5-spec container:
#   sudo docker run --rm -v /home/26kmc17/gem5:/workspace/gem5 \
#     gem5-spec bash -c "cd /workspace/gem5 && bash run_l3_latency_diagnostic.sh"
set -e
cd /workspace/gem5

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
WORKLOAD=tests/test-progs/memstress/bin/riscv/linux/memstress
WL_OPTS="4 4"   # 4 MB working set: fits L3 (16 MB), exceeds L2 (256 kB)

run_one() {
    local label="$1"; shift
    local outdir="m5out/diag_${label}"
    rm -rf "$outdir"
    $GEM5 --outdir="$outdir" $SCRIPT --cmd="$WORKLOAD" --options="$WL_OPTS" \
        "$@" 2>&1 | tail -1 > /dev/null
    local st cpi
    st=$( grep -E "^simTicks"         "$outdir/stats.txt" | awk '{print $2}')
    cpi=$(grep -E "^system\.cpu\.cpi" "$outdir/stats.txt" | awk '{print $2}')
    printf "%-22s %-15s %-12s\n" "$label" "$st" "$cpi"
}

echo "============================================"
echo " L3 latency diagnostic (memstress 4 MB x 4)"
echo "============================================"
printf "%-22s %-15s %-12s\n" "config" "simTicks" "CPI"

echo "--- READ sweep (write fixed at 40) ---"
for r in 10 40 80 160; do
    run_one "read${r}" --l3-read-latency="$r" --l3-write-latency=40
done

echo "--- WRITE sweep (read fixed at 40) ---"
for w in 4 40 100 200; do
    run_one "write${w}" --l3-read-latency=40 --l3-write-latency="$w"
done

echo "============================================"
echo "Expected: READ sweep simTicks rises; WRITE sweep simTicks flat."
echo "  -> model correct; L3 write latency hidden by blocking in-order CPU."
echo "If WRITE sweep also rises -> earlier flat result was a stale-build/"
echo "param-wiring issue. If READ sweep is also flat -> L3 not on crit path."
