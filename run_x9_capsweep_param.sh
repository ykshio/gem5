#!/bin/bash
# Task X9 (neptune): parametrized L3 capacity sweep — a thin, configurable
# sibling of run_x9_neptune.sh's X9-3 capsweep. It exists so we can drive ANY
# {capacity list} x {3 tech} matrix at ANY core count without editing (and
# risking a mid-run reread of) the main orchestrator.
#
# WHY SEPARATE FROM run_x9_neptune.sh:
#   - the 8-core 500M run is long-lived and bind-mounts the main script; editing
#     that file while bash is executing it can corrupt the run. A new file is safe.
#   - the single-core baseline needs a different CPI parse: with --num-cpus=1 gem5
#     emits "system.cpu.cpi" (NO index), so the main script's "^system.cpu[0-9]+.cpi"
#     misses it. Here we use [0-9]* to match both "system.cpu.cpi" and "system.cpuN.cpi".
#
# Carries over the deadlock fix from run_x9_neptune.sh: never `wait` with no pid
# args (that also targets the `exec > >(tee ...)` child, which never exits).
#
# Env knobs:
#   CAPS="4MB 8MB 16MB 32MB 64MB"  space-separated L3 sizes to sweep
#   NCPU=8                          cores per run (1 = single-core baseline)
#   MAXINSTS=500000000              per-core instruction cap (0 = run to completion)
#   PAR=8                           max concurrent gem5 processes
#   TAG_SUFFIX=""                   appended to every tag/outdir (e.g. "_1c") to
#                                   keep single-core rows from clobbering 8-core ones
#   LOGTAG="param"                  basename for the log/status files
#
# Each run writes m5out/x9n_<tech>_<size><TAG_SUFFIX>.row in the SAME column order
# as run_x9_neptune.sh so the rows aggregate uniformly.
cd /workspace/gem5 || exit 2

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
BIN=/binaries/mcf_s
INPUT=/inputs/inp.in

CAPS=${CAPS:-"4MB 8MB 16MB 32MB 64MB"}
NCPU=${NCPU:-8}
MAXINSTS=${MAXINSTS:-500000000}
PAR=${PAR:-8}
TAG_SUFFIX=${TAG_SUFFIX:-}
LOGTAG=${LOGTAG:-param}
CPU_TYPE=${CPU_TYPE:-TimingSimpleCPU}   # e.g. DerivO3CPU for the OoO validation

LOG=m5out/x9_${LOGTAG}.log
STATUS=m5out/x9_${LOGTAG}_status.txt
SUMMARY=m5out/x9_${LOGTAG}_summary.csv
mkdir -p m5out
exec > >(tee -a "$LOG") 2>&1

say () { echo "[x9-$LOGTAG $(date '+%H:%M:%S')] $*"; }
setstatus () { echo "$*" > "$STATUS"; say "STATUS -> $*"; }
maxinsts_arg () { [ "${1:-0}" -gt 0 ] && echo "--max-insts=$1"; }

HEADER="config,technology,l3_size,l3_read_lat,l3_write_lat,simTicks,simSeconds,simInsts,l3_hits,l3_misses,l3_missRate,l3_wbDirtyHits,cpi_avg,host_seconds"

# tech table: label|technology|read_lat|write_lat
TECHS=("sram|sram|40|40" "sot|sotmram|10|22" "stt|sttmram|10|35")

run_one () {
    local tag="$1" tech="$2" size="$3" rl="$4" wl="$5" cap="$6"
    local outdir="m5out/x9n_${tag}"
    local runcwd="m5out/x9n_${tag}_cwd"
    rm -rf "$outdir" "$runcwd" "$outdir.row"
    local i
    for ((i=0; i<NCPU; i++)); do mkdir -p "$runcwd/core$i"; done

    $GEM5 --outdir="$outdir" $SCRIPT \
        --cmd="$BIN" --options="$INPUT" --cwd="/workspace/gem5/$runcwd" \
        --num-cpus="$NCPU" --l3-size="$size" \
        --l3-read-latency="$rl" --l3-write-latency="$wl" \
        --cpu-type="$CPU_TYPE" \
        $(maxinsts_arg "$cap") \
        > "$outdir.log" 2>&1
    local s="$outdir/stats.txt"
    if [ ! -s "$s" ] || ! grep -q "^simInsts" "$s"; then
        say "[FAIL] $tag -- no stats (see $outdir.log)"; tail -20 "$outdir.log"; return 1
    fi
    local simTicks simInsts hits misses mrate wb cpiavg simSec hostSec
    simTicks=$(grep -E "^simTicks"   "$s" | awk '{print $2}')
    simInsts=$(grep -E "^simInsts"   "$s" | awk '{print $2}')
    simSec=$(  grep -E "^simSeconds"  "$s" | awk '{print $2}')
    hostSec=$( grep -E "^host_seconds" "$s" | awk '{print $2}')
    hits=$(  grep -E "^system\.l3\.overallHits::total"     "$s" | awk '{print $2}')
    misses=$(grep -E "^system\.l3\.overallMisses::total"   "$s" | awk '{print $2}')
    mrate=$( grep -E "^system\.l3\.overallMissRate::total" "$s" | awk '{print $2}')
    wb=$(    grep -E "^system\.l3\.WritebackDirty\.hits::total" "$s" | awk '{print $2}')
    # [0-9]* (not +) so single-core "system.cpu.cpi" is matched as well as "system.cpuN.cpi"
    cpiavg=$(grep -E "^system\.cpu[0-9]*\.cpi " "$s" | awk '{s+=$2; n++} END{if(n) printf "%.6f", s/n; else print "n/a"}')
    echo "${tag},${tech},${size},${rl},${wl},${simTicks},${simSec},${simInsts},${hits},${misses},${mrate},${wb},${cpiavg},${hostSec}" > "$outdir.row"
    say "[ok] $tag  ncpu=$NCPU size=$size rl/wl=${rl}/${wl}  miss=${mrate}  cpiAvg=${cpiavg}"
}

say "=================================================================="
say "X9 capsweep param: CAPS='$CAPS' NCPU=$NCPU CPU_TYPE=$CPU_TYPE MAXINSTS=$MAXINSTS PAR=$PAR TAG_SUFFIX='$TAG_SUFFIX'"
setstatus "RUNNING capsweep (CAPS='$CAPS' ncpu=$NCPU)"

pids=(); running=0; n_specs=0
for size in $CAPS; do
    for t in "${TECHS[@]}"; do
        IFS='|' read -r label tech rl wl <<< "$t"
        tag="${label}_${size}${TAG_SUFFIX}"
        run_one "$tag" "$tech" "$size" "$rl" "$wl" "$MAXINSTS" &
        pids+=($!); running=$((running+1)); n_specs=$((n_specs+1))
        # never bare-wait: that would block on the tee child forever
        if (( running >= PAR )); then wait -n "${pids[@]}" 2>/dev/null || wait "${pids[@]}"; running=$((running-1)); fi
    done
done
wait "${pids[@]}"

{ echo "$HEADER"; for size in $CAPS; do for t in "${TECHS[@]}"; do
    IFS='|' read -r label tech rl wl <<< "$t"
    cat "m5out/x9n_${label}_${size}${TAG_SUFFIX}.row" 2>/dev/null
done; done; } > "$SUMMARY"

# count DATA rows only: the HEADER line also contains commas, so subtract 1
got=$(( $(grep -c , "$SUMMARY") - 1 ))
if (( got >= n_specs )); then
    setstatus "DONE: capsweep ncpu=$NCPU complete ($got/$n_specs rows)"
else
    setstatus "PARTIAL: capsweep ncpu=$NCPU ($got/$n_specs rows) -- see m5out/x9n_*.log"
fi
say "SUMMARY -> $SUMMARY"; cat "$SUMMARY"
say "=================================================================="
