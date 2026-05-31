#!/bin/bash
# Task X1: does the L3 write-latency "hiding" seen on TimingSimpleCPU survive
# on an out-of-order core (DerivO3CPU)?
#
# On TimingSimpleCPU the store completes the moment L1D accepts it, so dirty
# writebacks into L3 never sit on the CPU critical path and --l3-write-latency
# has zero effect on simTicks. An OoO core can hold many outstanding accesses,
# so in principle the writeback latency could become visible. This script runs
# the same memstress 4 MB x 4 sweep used for TimingSimpleCPU, but with O3.
#
# Run INSIDE the gem5-spec container (cd /workspace/gem5 assumed), e.g.
#   sudo docker run --rm --user $(id -u):$(id -g) \
#     -v /home/26kmc17/gem5:/workspace/gem5 \
#     gem5-spec bash -c "cd /workspace/gem5 && bash run_o3_validation.sh"
set -e
cd /workspace/gem5

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
HELLO=tests/test-progs/hello/bin/riscv/linux/hello
MEMSTRESS=tests/test-progs/memstress/bin/riscv/linux/memstress
WL_OPTS="4 4"   # 4 MB buffer, 4 iterations (fits 16 MB L3, exceeds 256 kB L2)

echo "############################################"
echo "# Task X1 (a): is the O3 CPU built?"
echo "############################################"
if ls build/RISCV/cpu/o3/ >/dev/null 2>&1; then
    echo "[OK] O3 BUILT"
else
    echo "[NG] O3 NOT BUILT"
fi

echo
echo "############################################"
echo "# Task X1 (c): O3 + hello (minimal smoke test)"
echo "############################################"
rm -rf m5out/o3_hello
if $GEM5 --outdir=m5out/o3_hello $SCRIPT \
        --cmd="$HELLO" --cpu-type=DerivO3CPU 2>&1 | tail -15; then
    echo "[hello run returned 0]"
else
    echo "[NG] O3 hello run FAILED — sweep below will likely also fail"
fi

echo
echo "############################################"
echo "# Task X1 (d): L3 write_latency sweep on O3"
echo "#   (memstress 4 MB x 4, --l3-write-latency 4/10/50/100)"
echo "############################################"
printf "%-8s %-15s %-12s %-14s %-16s %-14s\n" \
    "wlat" "simTicks" "CPI" "simInsts" "l3WbDirtyHits" "l3Misses"

for w in 4 10 50 100; do
    outdir="m5out/o3_l3_w${w}"
    rm -rf "$outdir"
    $GEM5 --outdir="$outdir" $SCRIPT \
        --cmd="$MEMSTRESS" \
        --options="$WL_OPTS" \
        --cpu-type=DerivO3CPU \
        --l3-write-latency="$w" \
        > /dev/null 2>&1
    stats="$outdir/stats.txt"
    simTicks=$(grep -E "^simTicks"                                "$stats" | awk '{print $2}')
    # O3 may expose cpi under a slightly different key; grab the first cpi match
    # and also dump simInsts so CPI can be recomputed if the key name differs.
    cpi=$(     grep -E "system\.cpu\.cpi"                          "$stats" | head -1 | awk '{print $2}')
    insts=$(   grep -E "^simInsts"                                "$stats" | awk '{print $2}')
    l3wb=$(    grep -E "^system\.l3\.WritebackDirty\.hits::total"  "$stats" | awk '{print $2}')
    l3miss=$(  grep -E "^system\.l3\.overallMisses::total"        "$stats" | awk '{print $2}')
    printf "%-8s %-15s %-12s %-14s %-16s %-14s\n" \
        "$w" "${simTicks:-n/a}" "${cpi:-n/a}" "${insts:-n/a}" "${l3wb:-n/a}" "${l3miss:-n/a}"
done
echo "############################################"
echo "# Verdict:"
echo "#  - simTicks FLAT across w=4..100  -> hiding is fundamental (not CPU-model"
echo "#    specific); Task A finding holds on OoO too."
echo "#  - simTicks RISES with w          -> hiding was TimingSimpleCPU-specific;"
echo "#    L3 write latency does cost performance on an OoO core (note in thesis)."
echo "############################################"
