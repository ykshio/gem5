#!/bin/bash
# Write-stress sweep: fixed L3, fixed core count, sweep the STORE RATIO to locate
# the point where L3 write latency (SOT wl=22 vs STT wl=35) stops being hidden.
#
# Uses the wrstress microbench (build_wrstress_riscv.sh). Each core runs an
# independent wrstress process (se_mram_l3.py multi-program), buffer >> L3 share so
# dirty L2->L3 writebacks dominate. The -I cap bounds every point to the SAME
# instruction count so CPI/miss are directly comparable across write ratios.
#
# Carries the deadlock-safe wait (explicit pids, never bare `wait`) and the
# 1-core-safe CPI parse ([0-9]*) from run_x9_capsweep_param.sh.
#
# Env knobs:
#   WRATIOS="0 25 50 75 100"   store-ratio sweep points (percent)
#   L3SIZE=32MB  NCPU=8  MAXINSTS=500000000  PAR=8
#   BUF_MB=16    per-core buffer MB (8x16=128MB aggregate >> 32MB L3)
#   ITERS=100000 wrstress passes (large; -I cap is the real limiter)
#   CPU_TYPE=TimingSimpleCPU   (DerivO3CPU for an OoO pass)
#   TAG_SUFFIX="" LOGTAG=wrstress
cd /workspace/gem5 || exit 2

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
BIN=${BIN:-/workspace/gem5/tests/test-progs/wrstress/bin/riscv/linux/wrstress}

WRATIOS=${WRATIOS:-"0 25 50 75 100"}
L3SIZE=${L3SIZE:-32MB}
NCPU=${NCPU:-8}
MAXINSTS=${MAXINSTS:-500000000}
PAR=${PAR:-8}
BUF_MB=${BUF_MB:-16}
ITERS=${ITERS:-100000}
CPU_TYPE=${CPU_TYPE:-TimingSimpleCPU}
TAG_SUFFIX=${TAG_SUFFIX:-}
LOGTAG=${LOGTAG:-wrstress}

LOG=m5out/x9_${LOGTAG}.log
STATUS=m5out/x9_${LOGTAG}_status.txt
SUMMARY=m5out/x9_${LOGTAG}_summary.csv
mkdir -p m5out
exec > >(tee -a "$LOG") 2>&1
say(){ echo "[wrstress $(date '+%H:%M:%S')] $*"; }
setstatus(){ echo "$*" > "$STATUS"; say "STATUS -> $*"; }
maxinsts_arg(){ [ "${1:-0}" -gt 0 ] && echo "--max-insts=$1"; }

HEADER="config,technology,write_pct,l3_size,l3_read_lat,l3_write_lat,ncpu,cpu_type,simTicks,simSeconds,simInsts,l3_hits,l3_misses,l3_missRate,l3_wbDirtyHits,cpi_avg"
TECHS=("sram|sram|40|40" "sot|sotmram|10|22" "stt|sttmram|10|35")

run_one(){
    local tag="$1" tech="$2" rl="$3" wl="$4" wpct="$5"
    local outdir="m5out/x9n_${tag}" runcwd="m5out/x9n_${tag}_cwd"
    rm -rf "$outdir" "$runcwd" "$outdir.row"
    local i; for ((i=0;i<NCPU;i++)); do mkdir -p "$runcwd/core$i"; done
    $GEM5 --outdir="$outdir" $SCRIPT \
        --cmd="$BIN" --options="$BUF_MB $ITERS $wpct" --cwd="/workspace/gem5/$runcwd" \
        --num-cpus="$NCPU" --l3-size="$L3SIZE" \
        --l3-read-latency="$rl" --l3-write-latency="$wl" \
        --cpu-type="$CPU_TYPE" $(maxinsts_arg "$MAXINSTS") \
        > "$outdir.log" 2>&1
    local s="$outdir/stats.txt"
    if [ ! -s "$s" ] || ! grep -q "^simInsts" "$s"; then
        say "[FAIL] $tag -- no stats (see $outdir.log)"; tail -20 "$outdir.log"; return 1
    fi
    local simTicks simInsts hits misses mrate wb cpiavg simSec
    simTicks=$(grep -E "^simTicks" "$s"|awk '{print $2}')
    simInsts=$(grep -E "^simInsts" "$s"|awk '{print $2}')
    simSec=$(  grep -E "^simSeconds" "$s"|awk '{print $2}')
    hits=$(  grep -E "^system\.l3\.overallHits::total"     "$s"|awk '{print $2}')
    misses=$(grep -E "^system\.l3\.overallMisses::total"   "$s"|awk '{print $2}')
    mrate=$( grep -E "^system\.l3\.overallMissRate::total" "$s"|awk '{print $2}')
    wb=$(    grep -E "^system\.l3\.WritebackDirty\.hits::total" "$s"|awk '{print $2}')
    # [0-9]* so single-core "system.cpu.cpi" matches as well as "system.cpuN.cpi"
    cpiavg=$(grep -E "^system\.cpu[0-9]*\.cpi " "$s"|awk '{s+=$2;n++} END{if(n)printf "%.6f",s/n; else print "n/a"}')
    echo "${tag},${tech},${wpct},${L3SIZE},${rl},${wl},${NCPU},${CPU_TYPE},${simTicks},${simSec},${simInsts},${hits},${misses},${mrate},${wb},${cpiavg}" > "$outdir.row"
    say "[ok] $tag wpct=${wpct} miss=${mrate} cpi=${cpiavg} wbDirty=${wb}"
}

say "=================================================================="
say "write-stress: WRATIOS='$WRATIOS' L3=$L3SIZE NCPU=$NCPU CPU=$CPU_TYPE BUF=${BUF_MB}MB MAXINSTS=$MAXINSTS"
setstatus "RUNNING wrstress (WRATIOS='$WRATIOS' ncpu=$NCPU $CPU_TYPE)"
pids=(); running=0; n=0
for w in $WRATIOS; do
  for t in "${TECHS[@]}"; do
    IFS='|' read -r label tech rl wl <<< "$t"
    tag="${label}_w${w}${TAG_SUFFIX}"
    run_one "$tag" "$tech" "$rl" "$wl" "$w" &
    pids+=($!); running=$((running+1)); n=$((n+1))
    if (( running >= PAR )); then wait -n "${pids[@]}" 2>/dev/null || wait "${pids[@]}"; running=$((running-1)); fi
  done
done
wait "${pids[@]}"

{ echo "$HEADER"; for w in $WRATIOS; do for t in "${TECHS[@]}"; do
    IFS='|' read -r label tech rl wl <<< "$t"
    cat "m5out/x9n_${label}_w${w}${TAG_SUFFIX}.row" 2>/dev/null
done; done; } > "$SUMMARY"
got=$(( $(grep -c , "$SUMMARY") - 1 ))
if (( got >= n )); then setstatus "DONE: wrstress complete ($got/$n rows)"; else setstatus "PARTIAL: wrstress ($got/$n rows)"; fi
say "SUMMARY -> $SUMMARY"; cat "$SUMMARY"
say "=================================================================="
