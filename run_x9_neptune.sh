#!/bin/bash
# Task X9 / ROUND10: neptune-oriented orchestrator for the mcf_s rate sweep.
#
# WHY THIS EXISTS (vs run_x9_all.sh):
#   run_x9_all.sh runs every gem5 invocation SERIALLY and to COMPLETION. On a
#   1-core smoke that already meant >3h; the 8-core rate + capsweep would be
#   days of wall time while using only ONE of neptune's 24 threads. This script
#   keeps the same experiment matrix but adds the two things neptune needs:
#     1. PARALLELISM (PAR): run up to PAR gem5 processes at once. Each gem5
#        process is single-host-threaded, so PAR processes ~= PAR host threads.
#     2. INSTRUCTION CAP (MAXINSTS / -I): bound each core's run so a single
#        sweep finishes in a known time instead of "however long mcf test takes".
#
# PORTABILITY: the executable body references ONLY container paths
#   /workspace/gem5, /binaries (ro), /inputs (ro).
# The host-side real paths live solely on the `docker run -v` line, so the SAME
# command works on uranus and neptune -- only the -v sources change.
#
# MEMORY MATH (neptune = 62 GB): config defaults to TimingSimpleCPU + 512 MB
# guest mem + L3 <= 64 MB, so one run's host RSS is ~1 GB (estimate; not
# measured -- ROUND10 forbids running gem5 here). Peak host RAM ~= PAR * ~1 GB.
# PAR<=12 leaves comfortable headroom; the default is deliberately conservative.
#
# Tunables (environment variables):
#   PAR=4            max concurrent gem5 processes
#   MAXINSTS=0       per-core instruction cap (0 = run to completion = HEAVY).
#                    e.g. 500000000 bounds each core to 500M insts.
#   SMOKE_INSTS=200000000  instruction cap for the gating smoke (kept light on
#                    purpose so the gate is fast; set 0 to run smoke to the end).
#   DO_CAPSWEEP=1    also run X9-3 capacity sweep {16,32,64}MB after X9-2 (=1)
#   NCPU=8           cores per rate run
#
# Launch on neptune (Shiozawa, once; -d + restart so a host reboot auto-resumes):
#   sudo docker run -d --restart=on-failure:5 --name x9run \
#     --user $(id -u):$(id -g) \
#     -v <neptune_gem5_dir>:/workspace/gem5 \
#     -v <neptune_spec_binaries>:/binaries:ro \
#     -v <neptune_spec_data>:/inputs:ro \
#     -e PAR=8 -e MAXINSTS=500000000 \
#     gem5-spec bash -c "cd /workspace/gem5 && bash run_x9_neptune.sh"
#
# Watch from the host (bind mount, no docker needed):
#   tail -f <neptune_gem5_dir>/m5out/x9_neptune.log
#   cat     <neptune_gem5_dir>/m5out/x9_neptune_status.txt
cd /workspace/gem5 || exit 2

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
BIN=/binaries/mcf_s
INPUT=/inputs/inp.in

PAR=${PAR:-4}
MAXINSTS=${MAXINSTS:-0}
SMOKE_INSTS=${SMOKE_INSTS:-200000000}
DO_CAPSWEEP=${DO_CAPSWEEP:-1}
NCPU=${NCPU:-8}

LOG=m5out/x9_neptune.log
STATUS=m5out/x9_neptune_status.txt
mkdir -p m5out
exec > >(tee -a "$LOG") 2>&1

say () { echo "[x9-neptune $(date '+%H:%M:%S')] $*"; }
setstatus () { echo "$*" > "$STATUS"; say "STATUS -> $*"; }

maxinsts_arg () {   # $1 = cap; echo the flag (empty when cap is 0)
    [ "${1:-0}" -gt 0 ] && echo "--max-insts=$1"
}

say "=================================================================="
say "X9 neptune orchestrator: PAR=$PAR MAXINSTS=$MAXINSTS NCPU=$NCPU DO_CAPSWEEP=$DO_CAPSWEEP"

# ---------------------------------------------------------------- one run
# Writes its CSV row to <outdir>.row and its gem5 stdout to <outdir>.log so the
# parallel pool needs no shared mutable state. Returns nonzero if it made no stats.
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
    cpiavg=$(grep -E "^system\.cpu[0-9]+\.cpi " "$s" | awk '{s+=$2; n++} END{if(n) printf "%.6f", s/n; else print "n/a"}')
    echo "${tag},${tech},${size},${rl},${wl},${simTicks},${simSec},${simInsts},${hits},${misses},${mrate},${wb},${cpiavg},${hostSec}" > "$outdir.row"
    say "[ok] $tag  size=$size rl/wl=${rl}/${wl}  miss=${mrate}  cpiAvg=${cpiavg}  host_s=${hostSec}"
}

# ---------------------------------------------------------------- pool runner
# Args: CSV path, then any number of "tag|tech|size|rl|wl" specs. Runs them at
# most PAR at a time, then aggregates the per-run .row files into the CSV.
HEADER="config,technology,l3_size,l3_read_lat,l3_write_lat,simTicks,simSeconds,simInsts,l3_hits,l3_misses,l3_missRate,l3_wbDirtyHits,cpi_avg,host_seconds"
run_pool () {
    local csv="$1"; shift
    local running=0 spec tag tech size rl wl
    for spec in "$@"; do
        IFS='|' read -r tag tech size rl wl <<< "$spec"
        run_one "$tag" "$tech" "$size" "$rl" "$wl" "$MAXINSTS" &
        running=$((running+1))
        if (( running >= PAR )); then wait -n 2>/dev/null || wait; running=$((running-1)); fi
    done
    wait
    { echo "$HEADER"; cat m5out/x9n_*.row 2>/dev/null; } > "$csv"
    say "CSV -> $csv"; cat "$csv"
}

# ------------------------------------------------------------ X9-1 smoke gate
setstatus "RUNNING smoke (1 core, cap=$SMOKE_INSTS)"
SOUT=m5out/x9n_smoke; SCWD=m5out/x9n_smoke_cwd
rm -rf "$SOUT" "$SCWD"; mkdir -p "$SCWD"
$GEM5 --outdir="$SOUT" $SCRIPT \
    --cmd="$BIN" --options="$INPUT" --cwd="/workspace/gem5/$SCWD" \
    --num-cpus=1 --l3-size=32MB --l3-read-latency=40 --l3-write-latency=40 \
    $(maxinsts_arg "$SMOKE_INSTS") > "$SOUT.log" 2>&1
if [ -s "$SOUT/stats.txt" ] && grep -q "^simInsts" "$SOUT/stats.txt"; then
    SHOST=$(grep -E "^host_seconds" "$SOUT/stats.txt" | awk '{print $2}')
    say "smoke PASS (host_seconds=${SHOST})."
else
    setstatus "FAILED at smoke -- chain aborted (see $SOUT.log)"
    tail -20 "$SOUT.log"; exit 1
fi

# ------------------------------------------------------------ X9-2 rate (32MB)
setstatus "RUNNING X9-2 rate (8c x 3 tech, PAR=$PAR)"
run_pool m5out/x9n_rate_summary.csv \
    "sram|sram|32MB|40|40" \
    "sot|sotmram|32MB|10|22" \
    "stt|sttmram|32MB|10|35"
if [ "$(grep -c , m5out/x9n_rate_summary.csv)" -lt 4 ]; then
    setstatus "PARTIAL: X9-2 incomplete -- see m5out/x9n_*.log"; exit 1
fi

# ------------------------------------------------------------ X9-3 capsweep
if [ "$DO_CAPSWEEP" = "1" ]; then
    setstatus "RUNNING X9-3 capsweep ({16,32,64}MB x 3 tech, PAR=$PAR)"
    run_pool m5out/x9n_capsweep_summary.csv \
        "sram_16MB|sram|16MB|40|40"   "sot_16MB|sotmram|16MB|10|22"   "stt_16MB|sttmram|16MB|10|35" \
        "sram_32MB|sram|32MB|40|40"   "sot_32MB|sotmram|32MB|10|22"   "stt_32MB|sttmram|32MB|10|35" \
        "sram_64MB|sram|64MB|40|40"   "sot_64MB|sotmram|64MB|10|22"   "stt_64MB|sttmram|64MB|10|35"
    if [ "$(grep -c , m5out/x9n_capsweep_summary.csv)" -ge 10 ]; then
        setstatus "DONE: smoke + X9-2 + X9-3 complete"
    else
        setstatus "PARTIAL: X9-3 incomplete -- see m5out/x9n_*.log"
    fi
else
    setstatus "DONE: smoke + X9-2 complete (X9-3 skipped, DO_CAPSWEEP=0)"
fi

say "X9 neptune orchestrator finished."
say "=================================================================="
