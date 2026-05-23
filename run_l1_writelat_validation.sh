#!/bin/bash
# Validation: prove that BaseCache::writeLatency actually charges the
# data array on write hits. Uses cachewrite (16 KB buffer, write+read
# interleaved) so almost every CPU write hits L1D after the first pass.
# Sweep the L1D write_latency from 4 to 100 and confirm simTicks scales.
set -e
cd /workspace/gem5

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
WORKLOAD=tests/test-progs/cachewrite/bin/riscv/linux/cachewrite

echo "============================================"
echo " L1D write_latency validation sweep"
echo " (workload: cachewrite, 16 KB buffer × 200 passes)"
echo "============================================"
printf "%-10s %-15s %-15s\n" "wlat" "simTicks" "CPI"

for w in 4 10 50 100; do
    outdir="m5out/l1d_w${w}"
    rm -rf "$outdir"
    $GEM5 --outdir="$outdir" $SCRIPT \
        --cmd="$WORKLOAD" \
        --l1d-write-latency="$w" \
        2>&1 | tail -1 > /dev/null
    simTicks=$(grep -E "^simTicks" "$outdir/stats.txt" | awk '{print $2}')
    cpi=$(grep -E "^system\.cpu\.cpi" "$outdir/stats.txt" | awk '{print $2}')
    printf "%-10s %-15s %-15s\n" "$w" "$simTicks" "$cpi"
done
echo "============================================"
echo "Implementation is wired up correctly if simTicks rises monotonically."
