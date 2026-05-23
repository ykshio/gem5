#!/bin/bash
# Round-2 master runner: rebuilds memstress (parameterized) then runs
# both the WS=4MB sweep (F) and the L1 SRAM vs MRAM comparison (H)
# in one Docker round. Output lands under results/2026-05-23/.
set -e
cd /workspace/gem5

echo "============================================"
echo " Step 1: rebuild memstress (now argv[1]=size_mb)"
echo "============================================"
bash build_memstress_riscv.sh

echo
echo "============================================"
echo " Step 2: F - WS=4MB sweep (L3 hit mixed)"
echo "============================================"
bash run_ws4mb_sweep.sh

echo
echo "============================================"
echo " Step 3: H - L1 SRAM vs MRAM head-to-head"
echo "============================================"
bash run_l1_sram_vs_mram.sh

echo
echo "ALL DONE"
