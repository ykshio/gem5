#!/bin/bash
# A/B test of asymmetric write latency on hello workload.
set -e
cd /workspace/gem5
rm -rf m5out_A m5out_B

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_test.py
WORKLOAD=tests/test-progs/hello/bin/riscv/linux/hello

echo "=== Run A: default (write_latency = data_latency = 2) ==="
$GEM5 --outdir=m5out_A $SCRIPT \
    --cpu-type=TimingSimpleCPU \
    --cmd=$WORKLOAD --caches --l2cache 2>&1 | tail -2

echo "=== Run B: L1_DCache.write_latency = 100 ==="
$GEM5 --outdir=m5out_B $SCRIPT --l1d-write-latency=100 \
    --cpu-type=TimingSimpleCPU \
    --cmd=$WORKLOAD --caches --l2cache 2>&1 | tail -2

echo "=== A simTicks ==="
grep -E "simTicks|simSeconds" m5out_A/stats.txt
echo "=== B simTicks (wlat=100) ==="
grep -E "simTicks|simSeconds" m5out_B/stats.txt
echo "=== L1D write/read hits A ==="
grep -E "system.cpu.dcache.(WriteReq_hits|ReadReq_hits|overallHits)::" m5out_A/stats.txt | head -10
echo "=== L1D write/read hits B ==="
grep -E "system.cpu.dcache.(WriteReq_hits|ReadReq_hits|overallHits)::" m5out_B/stats.txt | head -10
