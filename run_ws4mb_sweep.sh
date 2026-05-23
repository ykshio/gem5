#!/bin/bash
# Round-2 F: writeback hiding refutation with L3 hits.
# Uses memstress at 4 MB (fits in L3=16MB) so we get a mixed hit/miss
# regime and can see whether L3 wlat matters when there ARE L3 hits.
#
# Output: results/2026-05-23/ws4mb/{sweep.csv, rlat.csv, per-run stats}
set -e
cd /workspace/gem5

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
WORKLOAD=tests/test-progs/memstress/bin/riscv/linux/memstress
WS_MB=4
OUTROOT=results/2026-05-23/ws4mb
mkdir -p "$OUTROOT"

extract() {
    grep -E "^$2" "$1" | head -1 | awk '{print $2}'
}

run_cfg() {
    local label="$1" rlat="$2" wlat="$3" bufs="$4" csv="$5"
    local outdir="$OUTROOT/${label}"
    rm -rf "$outdir"
    echo "[run] $label : L3 rlat=$rlat wlat=$wlat buffers=$bufs (WS=${WS_MB}MB)"
    $GEM5 --outdir="$outdir" $SCRIPT \
        --cmd="$WORKLOAD" \
        --options="$WS_MB" \
        --l3-read-latency="$rlat" \
        --l3-write-latency="$wlat" \
        --l3-write-buffers="$bufs" 2>&1 | tail -3
    local f="$outdir/stats.txt"
    local sim=$(extract "$f" "simTicks")
    local cpi=$(extract "$f" "system\.cpu\.cpi")
    local hits=$(extract "$f" "system\.l3\.overallHits::total")
    local miss=$(extract "$f" "system\.l3\.overallMisses::total")
    local acc=$(extract "$f" "system\.l3\.overallAccesses::total")
    local hr=$(extract "$f" "system\.l3\.overallMissRate::total")
    local wb=$(extract "$f" "system\.l3\.writebacks::total")
    local host=$(extract "$f" "hostSeconds")
    [ -z "$hits" ] && hits=0
    echo "$label,$rlat,$wlat,$bufs,$sim,$cpi,$hits,$miss,$acc,$hr,$wb,$host" >> "$csv"
}

# ---- F-1/F-2: 6 configs at rlat=10 (MRAM read) or rlat=40 (SRAM read) ----
# To mirror the 32MB sweep we keep rlat tied to wlat regime:
#   SRAM      -> rlat=40, wlat=40
#   MRAM 35   -> rlat=10, wlat=35
#   MRAM 50   -> rlat=10, wlat=50
CSV="$OUTROOT/sweep.csv"
echo "config,l3_rlat,l3_wlat,l3_write_buffers,simTicks,cpi,l3_hits,l3_misses,l3_accesses,l3_miss_rate,l3_writebacks,host_s" > "$CSV"

run_cfg sram_buf16    40 40 16 "$CSV"
run_cfg mram35_buf16  10 35 16 "$CSV"
run_cfg mram50_buf16  10 50 16 "$CSV"
run_cfg sram_buf4     40 40  4 "$CSV"
run_cfg mram35_buf4   10 35  4 "$CSV"
run_cfg mram50_buf4   10 50  4 "$CSV"

# ---- F-rlat: isolate L3 read-latency effect (wlat=40 fixed) ----
RLAT_CSV="$OUTROOT/rlat.csv"
echo "config,l3_rlat,l3_wlat,l3_write_buffers,simTicks,cpi,l3_hits,l3_misses,l3_accesses,l3_miss_rate,l3_writebacks,host_s" > "$RLAT_CSV"

run_cfg rlat10_wlat40 10 40 16 "$RLAT_CSV"
run_cfg rlat40_wlat40 40 40 16 "$RLAT_CSV"

echo
echo "=== sweep.csv ==="
cat "$CSV"
echo
echo "=== rlat.csv ==="
cat "$RLAT_CSV"
