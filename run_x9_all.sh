#!/bin/bash
# Task X9 ORCHESTRATOR: run the whole mcf_s chain unattended, in order, with
# gating, inside ONE container. Designed to be launched detached (docker -d)
# so it survives SSH disconnect -- you enter the sudo password once at launch
# and can leave. All progress/results land on the bind-mounted m5out/ so they
# can be read from the host without docker.
#
# Chain:
#   X9-1 smoke (1 core)                 -- gate: must produce stats (simInsts)
#   X9-2 rate  (8 core x 3 tech)        -- runs only if smoke passed
#   X9-3 capsweep (8 core x 3 sizes)    -- runs only if every X9-2 run < 6h
#
# Launch (detached, password entered once, survives logout):
#   sudo docker run -d --rm --name x9run --user $(id -u):$(id -g) \
#     -v /home/26kmc17/gem5:/workspace/gem5 \
#     -v /home/shiozawa/inventory-results/workspace_backup_check/spec_binaries:/binaries:ro \
#     -v /home/shiozawa/cal/experiment/spec_data:/inputs:ro \
#     gem5-spec bash -c "cd /workspace/gem5 && bash run_x9_all.sh"
#
# Watch from the host (no docker needed -- it's a bind mount):
#   tail -f /home/26kmc17/gem5/m5out/x9_all.log
#   cat     /home/26kmc17/gem5/m5out/x9_all_status.txt
cd /workspace/gem5

LOG=m5out/x9_all.log
STATUS=m5out/x9_all_status.txt
mkdir -p m5out
# Everything below goes to the log file (and the container's docker logs).
exec > >(tee -a "$LOG") 2>&1

GATE_6H=21600   # 6 hours in seconds, the X9-3 cutoff per ROUND9

say () { echo "[x9-all $(date '+%H:%M:%S')] $*"; }
setstatus () { echo "$*" > "$STATUS"; say "STATUS -> $*"; }

say "=================================================================="
say "X9 orchestrator start. Chain: smoke -> rate(8c) -> capsweep(cond)."
setstatus "RUNNING X9-1 smoke"

# ----------------------------- X9-1 smoke -----------------------------
bash run_mcf_se_smoke.sh || true
SMOKE_STATS=m5out/x9_smoke/stats.txt
if [ -s "$SMOKE_STATS" ] && grep -q "^simInsts" "$SMOKE_STATS"; then
    SMOKE_HOST=$(grep -E "^host_seconds" "$SMOKE_STATS" | awk '{print $2}')
    say "X9-1 smoke PASS (host_seconds=${SMOKE_HOST})."
else
    setstatus "FAILED at X9-1 smoke (no stats) -- chain aborted"
    say "mcf_s smoke did not complete. Not starting the 8-core runs."
    say "Likely: dynamic-link error / bad input / relative aux file needed."
    exit 1
fi

# ----------------------------- X9-2 rate ------------------------------
setstatus "RUNNING X9-2 rate (8c x 3 tech)"
say "Starting X9-2: 8-core mcf_s rate, L3 32MB, SRAM/SOT/STT."
bash run_mcf_se_rate_8core.sh || true
RATE_CSV=m5out/x9_mcf_rate_summary.csv
if [ ! -s "$RATE_CSV" ] || [ "$(grep -c , "$RATE_CSV")" -lt 4 ]; then
    setstatus "PARTIAL: X9-2 incomplete -- see $RATE_CSV / *.log"
    say "X9-2 did not produce a full 3-row CSV. Stopping before X9-3."
    exit 1
fi
say "X9-2 done. CSV:"
cat "$RATE_CSV"

# Gate for X9-3: every X9-2 run must be under 6h (host_seconds column = $14).
MAXHOST=$(awk -F, 'NR>1 {if($14+0>m) m=$14+0} END{printf "%.0f", m}' "$RATE_CSV")
say "X9-2 slowest run host_seconds=${MAXHOST} (gate=${GATE_6H})."

# --------------------------- X9-3 capsweep ----------------------------
if [ "${MAXHOST:-0}" -gt 0 ] && [ "${MAXHOST:-0}" -le "$GATE_6H" ]; then
    setstatus "RUNNING X9-3 capsweep ({16,32,64}MB x 3 tech)"
    say "Gate OK (<=6h). Starting X9-3 capacity sweep, 9 runs."
    bash run_mcf_se_rate_capsweep.sh || true
    CAP_CSV=m5out/x9_mcf_capsweep_summary.csv
    if [ -s "$CAP_CSV" ] && [ "$(grep -c , "$CAP_CSV")" -ge 10 ]; then
        say "X9-3 done. CSV:"; cat "$CAP_CSV"
        setstatus "DONE: X9-1 + X9-2 + X9-3 all complete"
    else
        setstatus "PARTIAL: X9-3 incomplete -- see $CAP_CSV / *.log"
    fi
else
    setstatus "DONE: X9-1 + X9-2 complete; X9-3 SKIPPED (run >6h or no timing)"
    say "Skipping X9-3: slowest X9-2 run exceeded the 6h gate (or no timing)."
fi

say "X9 orchestrator finished."
say "=================================================================="
