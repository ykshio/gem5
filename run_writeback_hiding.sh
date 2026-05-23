#!/bin/bash
# Refutation experiment for the "writeback path hides MRAM write latency"
# hypothesis. Sweeps (write_buffers x L3 wlat) on the 32MB memstress
# workload (exceeds L3=16MB so writebacks actually pressure the path).
#
# Output: results/2026-05-23/writeback_hiding/{sweep.csv, per-run stats dirs}
set -e
cd /workspace/gem5

GEM5=build/RISCV/gem5.opt
SCRIPT=configs/example/se_mram_l3.py
WORKLOAD=tests/test-progs/memstress/bin/riscv/linux/memstress
OUTROOT=results/2026-05-23/writeback_hiding
mkdir -p "$OUTROOT"

CSV="$OUTROOT/sweep.csv"
echo "config,l3_wlat,l3_write_buffers,simTicks,cpi,l3_hits,l3_misses,l3_writebacks,host_s" > "$CSV"

run_cfg() {
    local label="$1" wlat="$2" bufs="$3"
    local outdir="$OUTROOT/${label}"
    rm -rf "$outdir"
    echo "[run] $label : L3 wlat=$wlat buffers=$bufs"
    $GEM5 --outdir="$outdir" $SCRIPT \
        --cmd="$WORKLOAD" \
        --l3-read-latency=10 \
        --l3-write-latency="$wlat" \
        --l3-write-buffers="$bufs" 2>&1 | tail -3
    local f="$outdir/stats.txt"
    local sim=$(grep -E "^simTicks" "$f" | awk '{print $2}')
    local cpi=$(grep -E "^system\.cpu\.cpi" "$f" | awk '{print $2}')
    local hits=$(grep -E "^system\.l3\.overallHits::total" "$f" | awk '{print $2}')
    local miss=$(grep -E "^system\.l3\.overallMisses::total" "$f" | awk '{print $2}')
    local wb=$(grep -E "^system\.l3\.writebacks::total" "$f" | head -1 | awk '{print $2}')
    [ -z "$wb" ] && wb=$(grep -E "^system\.l3\.writebacks" "$f" | head -1 | awk '{print $2}')
    local host=$(grep -E "^hostSeconds" "$f" | awk '{print $2}')
    echo "$label,$wlat,$bufs,$sim,$cpi,$hits,$miss,$wb,$host" >> "$CSV"
}

# SRAM baseline (symmetric 40/40) at both buffer depths for reference
run_cfg sram_buf16        40 16
run_cfg sram_buf4         40 4

# MRAM 10/35 and 10/50 at default buffers=16 (the "no difference" suspect)
run_cfg mram35_buf16      35 16
run_cfg mram50_buf16      50 16

# MRAM 10/35 and 10/50 at buffers=4 (back-pressure on)
run_cfg mram35_buf4       35 4
run_cfg mram50_buf4       50 4

echo
echo "=== Sweep CSV ==="
cat "$CSV"
