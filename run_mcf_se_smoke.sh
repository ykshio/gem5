#!/bin/bash
# Task X9-1: mcf_s SE-mode smoke (1 core x L3 32MB x SRAM x test input).
#
# Goal: confirm the RISC-V SE binary mcf_s runs to completion under
# se_mram_l3.py and measure its wall/sim time + CPI. This must pass before
# the 8-core rate sweep (X9-2) is worth attempting.
#
# I/O design notes (differ slightly from the ROUND9 sketch, on purpose):
#   * The existing se_mram_l3.py is already generic (--cmd/--options), so no
#     "--benchmark" registry is needed -- we pass the binary via --cmd and the
#     input file via --options.
#   * The input is given as an ABSOLUTE path (/inputs/inp.in) so it is found
#     regardless of cwd.
#   * process cwd is set to a WRITABLE dir under m5out (--cwd). /inputs is
#     mounted :ro and lives under /home/shiozawa where uid 26kmc17 cannot
#     write, so if mcf opens an output file in cwd it would fail there. A
#     writable cwd avoids that. Any files mcf creates land in $RUNCWD (host
#     side: gem5/m5out/x9_smoke_cwd) where we can inspect them afterwards.
#
# Run INSIDE the gem5-spec container with the two SPEC mounts, e.g.:
#   sudo docker run --rm --user $(id -u):$(id -g) \
#     -v /home/26kmc17/gem5:/workspace/gem5 \
#     -v /home/shiozawa/inventory-results/workspace_backup_check/spec_binaries:/binaries:ro \
#     -v /home/shiozawa/cal/experiment/spec_data:/inputs:ro \
#     gem5-spec bash -c "cd /workspace/gem5 && bash run_mcf_se_smoke.sh"
set -e
cd /workspace/gem5

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
BIN=/binaries/mcf_s
INPUT=/inputs/inp.in
OUTDIR=m5out/x9_smoke
RUNCWD=m5out/x9_smoke_cwd   # writable working dir for the simulated mcf process

echo "=== X9-1 mcf_s SE smoke ==="
echo "binary : $BIN"
echo "input  : $INPUT"
ls -l "$BIN" "$INPUT" 2>&1 || { echo "[FATAL] binary or input missing -- check the -v mounts"; exit 2; }
echo "--- /inputs contents (what aux files exist next to inp.in) ---"
ls -la /inputs 2>&1 || true
echo

rm -rf "$OUTDIR" "$RUNCWD"
mkdir -p "$RUNCWD"

# 1 core, shared-L3 layout collapses to single-core; L3=32MB SRAM-class 40/40.
set +e
$GEM5 --outdir="$OUTDIR" $SCRIPT \
    --cmd="$BIN" --options="$INPUT" --cwd="/workspace/gem5/$RUNCWD" \
    --num-cpus=1 --l3-size=32MB \
    --l3-read-latency=40 --l3-write-latency=40 \
    2>&1 | tail -40
RC=${PIPESTATUS[0]}
set -e
echo
echo "gem5 exit code: $RC"

S="$OUTDIR/stats.txt"
if [ -s "$S" ] && grep -q "^simInsts" "$S"; then
    echo "=== SMOKE PASS: stats.txt produced ==="
    for k in simInsts simOps simTicks simSeconds host_seconds \
             "system.cpu.cpi " "system.l3.overallMissRate::total" \
             "system.l3.overallHits::total" "system.l3.overallMisses::total"; do
        grep -E "^${k}" "$S" | head -1
    done
    echo "--- files mcf wrote into cwd ($RUNCWD) ---"
    ls -la "$RUNCWD" 2>&1 || true
else
    echo "=== SMOKE FAIL: no simInsts in $S ==="
    echo "Check: dynamic-link error (needs static bin?), bad input path, or"
    echo "mcf needing an aux file via relative path (then set --cwd=/inputs and"
    echo "drop :ro / accept that output-file writes may fail)."
fi
