#!/bin/bash
# Task X9-3: mcf_s 8-core rate, L3 capacity sweep {16,32,64}MB x 3 technologies
# = 9 runs. Only run this if X9-2's single run came in under ~6h wall time.
#
# This is the X6 (memstress) experiment re-done with a REAL benchmark: it lets
# P11 (the B4 single-core table) be replaced by an "mcf_s x 8-core rate" version
# directly comparable to the memstress cliff story.
#
# Same mounts as X9-2. Run INSIDE gem5-spec:
#   sudo docker run --rm --user $(id -u):$(id -g) \
#     -v /home/26kmc17/gem5:/workspace/gem5 \
#     -v /home/shiozawa/inventory-results/workspace_backup_check/spec_binaries:/binaries:ro \
#     -v /home/shiozawa/cal/experiment/spec_data:/inputs:ro \
#     gem5-spec bash -c "cd /workspace/gem5 && bash run_mcf_se_rate_capsweep.sh"
set -e
cd /workspace/gem5

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
BIN=/binaries/mcf_s
INPUT=/inputs/inp.in
NCPU=8

CSV=m5out/x9_mcf_capsweep_summary.csv
HEADER="config,technology,l3_size,l3_read_lat,l3_write_lat,simTicks,simSeconds,simInsts,l3_hits,l3_misses,l3_missRate,l3_wbDirtyHits,cpi_avg,host_seconds"
ROWS=()
printf "%-12s %-7s %-9s %-15s %-11s %-11s %-9s\n" \
    "config" "l3size" "rl/wl" "simTicks" "l3Misses" "l3MissRate" "cpiAvg"

run_one () {
    local tag="$1" tech="$2" size="$3" rl="$4" wl="$5"
    local outdir="m5out/x9cap_${tag}"
    local runcwd="m5out/x9cap_${tag}_cwd"
    rm -rf "$outdir" "$runcwd"
    local i
    for ((i=0; i<NCPU; i++)); do mkdir -p "$runcwd/core$i"; done

    $GEM5 --outdir="$outdir" $SCRIPT \
        --cmd="$BIN" --options="$INPUT" --cwd="/workspace/gem5/$runcwd" \
        --num-cpus="$NCPU" --l3-size="$size" \
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
    cpiavg=$(grep -E "^system\.cpu[0-9]+\.cpi " "$s" | awk '{s+=$2; n++} END{if(n) printf "%.6f", s/n; else print "n/a"}')
    printf "%-12s %-7s %-9s %-15s %-11s %-11s %-9s\n" \
        "$tag" "$size" "${rl}/${wl}" "$simTicks" "${misses}" "${mrate}" "${cpiavg}"
    ROWS+=("${tag},${tech},${size},${rl},${wl},${simTicks},${simSec},${simInsts},${hits},${misses},${mrate},${wb},${cpiavg},${hostSec}")
}

for size in 16MB 32MB 64MB; do
    echo "=== L3 = $size ==="
    run_one "sram_${size}" sram    "$size" 40 40
    run_one "sot_${size}"  sotmram "$size" 10 22
    run_one "stt_${size}"  sttmram "$size" 10 35
    echo
done

{ echo "$HEADER"; printf '%s\n' "${ROWS[@]}"; } > "$CSV"
echo "CSV: $CSV"
cat "$CSV"
