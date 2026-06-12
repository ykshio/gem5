#!/bin/bash
# Task X9-2: mcf_s 8-core SPEC-rate x shared-L3 32MB x 3 technologies.
#
# 8 cores each run an INDEPENDENT copy of mcf_s (= SPEC rate), private L1+L2
# per core, shared 32MB L3. Sweep the 3 L3 technologies (same rl/wl grid as X6):
#       SRAM 40/40 | SOT 10/22 | STT 10/35
# Capacity identical across the 3 -> miss-rate is the same; only read latency
# differs (write stays hidden, per X1/X3/X7). So the 3 rows isolate the MRAM
# read-latency benefit at the multi-core / real-benchmark level.
#
# Prereq: run_mcf_se_smoke.sh (X9-1) must PASS first. If the smoke showed mcf
# writing a fixed-name output file into its cwd, the per-core cwd below keeps
# the 8 copies from clobbering each other.
#
# Run INSIDE gem5-spec with the SPEC mounts (same as the smoke):
#   sudo docker run --rm --user $(id -u):$(id -g) \
#     -v /home/26kmc17/gem5:/workspace/gem5 \
#     -v /home/shiozawa/inventory-results/workspace_backup_check/spec_binaries:/binaries:ro \
#     -v /home/shiozawa/cal/experiment/spec_data:/inputs:ro \
#     gem5-spec bash -c "cd /workspace/gem5 && bash run_mcf_se_rate_8core.sh"
set -e
cd /workspace/gem5

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
BIN=/binaries/mcf_s
INPUT=/inputs/inp.in
NCPU=8
L3SIZE=32MB

CSV=m5out/x9_mcf_rate_summary.csv
HEADER="config,technology,l3_size,l3_read_lat,l3_write_lat,simTicks,simSeconds,simInsts,l3_hits,l3_misses,l3_missRate,l3_wbDirtyHits,cpi_avg,host_seconds"
ROWS=()
printf "%-10s %-7s %-9s %-15s %-11s %-11s %-11s %-9s\n" \
    "config" "l3size" "rl/wl" "simTicks" "l3Hits" "l3Misses" "l3MissRate" "cpiAvg"

run_one () {
    local tag="$1" tech="$2" rl="$3" wl="$4"
    local outdir="m5out/x9_${tag}"
    local runcwd="m5out/x9_${tag}_cwd"
    rm -rf "$outdir" "$runcwd"
    # Pre-create a per-core working dir for each of the 8 rate copies.
    local i
    for ((i=0; i<NCPU; i++)); do mkdir -p "$runcwd/core$i"; done

    $GEM5 --outdir="$outdir" $SCRIPT \
        --cmd="$BIN" --options="$INPUT" --cwd="/workspace/gem5/$runcwd" \
        --num-cpus="$NCPU" --l3-size="$L3SIZE" \
        --l3-read-latency="$rl" --l3-write-latency="$wl" \
        > "$outdir.log" 2>&1
    local s="$outdir/stats.txt"
    if [ ! -s "$s" ] || ! grep -q "^simInsts" "$s"; then
        echo "[FAIL] $tag produced no stats -- see $outdir.log"; tail -20 "$outdir.log"; return 1
    fi
    local simTicks simInsts hits misses mrate wb cpiavg simSec hostSec
    simTicks=$(grep -E "^simTicks"  "$s" | awk '{print $2}')
    simInsts=$(grep -E "^simInsts"  "$s" | awk '{print $2}')
    simSec=$(  grep -E "^simSeconds" "$s" | awk '{print $2}')
    hostSec=$( grep -E "^host_seconds" "$s" | awk '{print $2}')
    hits=$(  grep -E "^system\.l3\.overallHits::total"     "$s" | awk '{print $2}')
    misses=$(grep -E "^system\.l3\.overallMisses::total"   "$s" | awk '{print $2}')
    mrate=$( grep -E "^system\.l3\.overallMissRate::total" "$s" | awk '{print $2}')
    wb=$(    grep -E "^system\.l3\.WritebackDirty\.hits::total" "$s" | awk '{print $2}')
    # average CPI over the 8 cores (stat is system.cpu0.cpi ... system.cpu7.cpi)
    cpiavg=$(grep -E "^system\.cpu[0-9]+\.cpi " "$s" | awk '{s+=$2; n++} END{if(n) printf "%.6f", s/n; else print "n/a"}')
    printf "%-10s %-7s %-9s %-15s %-11s %-11s %-11s %-9s\n" \
        "$tag" "$L3SIZE" "${rl}/${wl}" "$simTicks" "${hits}" "${misses}" "${mrate}" "${cpiavg}"
    ROWS+=("${tag},${tech},${L3SIZE},${rl},${wl},${simTicks},${simSec},${simInsts},${hits},${misses},${mrate},${wb},${cpiavg},${hostSec}")
}

echo "=== X9-2: mcf_s 8-core rate, shared L3 ${L3SIZE}, 3 technologies ==="
run_one sram sram 40 40
run_one sot  sotmram 10 22
run_one stt  sttmram 10 35

echo
{ echo "$HEADER"; printf '%s\n' "${ROWS[@]}"; } > "$CSV"
echo "CSV: $CSV"
cat "$CSV"
echo
echo "Read it as: with capacity fixed at ${L3SIZE}, the 3 rows share miss-rate"
echo "(same capacity) and differ only by L3 read latency. SOT/STT (read=10)"
echo "should beat SRAM (read=40) on CPI; SOT==STT confirms write is hidden."
