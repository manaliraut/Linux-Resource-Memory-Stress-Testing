#!/bin/bash
# Experiment 1: Baseline (FIXED)
# No memory limits - observe natural PSI growth and latency

EXP_DIR=/home/durgaaishwarya/os_project/results/exp1_baseline
TRIAL=${1:-1}
OUT_DIR="$EXP_DIR/trial_$TRIAL"
mkdir -p "$OUT_DIR"
CGROUP=/sys/fs/cgroup/os_exp1

echo "========================================" | tee "$OUT_DIR/experiment.log"
echo " EXPERIMENT 1: BASELINE - Trial $TRIAL"  | tee -a "$OUT_DIR/experiment.log"
echo "========================================" | tee -a "$OUT_DIR/experiment.log"
echo "Start time: $(date)" | tee -a "$OUT_DIR/experiment.log"

sudo mkdir -p "$CGROUP"

# Start metric collection
/home/durgaaishwarya/os_project/scripts/collect_metrics.sh "$OUT_DIR" "$CGROUP" &
METRICS_PID=$!
echo "Metrics PID: $METRICS_PID" | tee -a "$OUT_DIR/experiment.log"

# Start HTTP server
taskset -c 0 python3 /home/durgaaishwarya/os_project/scripts/server.py &
SERVER_PID=$!
echo "Server PID: $SERVER_PID" | tee -a "$OUT_DIR/experiment.log"
sleep 3

# Verify server is up before proceeding
if ! curl -s http://localhost:8080/ > /dev/null; then
    echo "ERROR: Server not responding!" | tee -a "$OUT_DIR/experiment.log"
    kill $METRICS_PID 2>/dev/null
    exit 1
fi
echo "Server verified OK" | tee -a "$OUT_DIR/experiment.log"

# Baseline wrk - NO stress
echo "--- Baseline latency (no stress) ---" | tee -a "$OUT_DIR/experiment.log"
taskset -c 1 wrk -t2 -c10 -d30s --latency http://localhost:8080/ > "$OUT_DIR/wrk_baseline.txt" 2>&1
cat "$OUT_DIR/wrk_baseline.txt" | tee -a "$OUT_DIR/experiment.log"

# Record oom_score BEFORE stress
echo "--- oom_score BEFORE stress ---" | tee -a "$OUT_DIR/experiment.log"
echo "oom_score: $(cat /proc/$SERVER_PID/oom_score)" | tee -a "$OUT_DIR/experiment.log"
echo "oom_score_adj: $(cat /proc/$SERVER_PID/oom_score_adj)" | tee -a "$OUT_DIR/experiment.log"

# PSI before stress
echo "--- PSI BEFORE stress ---" | tee -a "$OUT_DIR/experiment.log"
cat /proc/pressure/memory | tee -a "$OUT_DIR/experiment.log"

# Start stress-ng with SAFE 50% to avoid killing server in baseline
echo "--- Starting stress-ng (50% RAM, safe for baseline) ---" | tee -a "$OUT_DIR/experiment.log"
stress-ng --vm 1 --vm-bytes 50% --vm-keep --timeout 60s &
STRESS_PID=$!
echo "stress-ng PID: $STRESS_PID" | tee -a "$OUT_DIR/experiment.log"

sleep 15  # let pressure build

# Verify server still alive
if curl -s http://localhost:8080/ > /dev/null; then
    echo "--- Latency UNDER stress ---" | tee -a "$OUT_DIR/experiment.log"
    taskset -c 1 wrk -t2 -c10 -d30s --latency http://localhost:8080/ > "$OUT_DIR/wrk_under_stress.txt" 2>&1
    cat "$OUT_DIR/wrk_under_stress.txt" | tee -a "$OUT_DIR/experiment.log"
else
    echo "Server died under stress - note in results" | tee -a "$OUT_DIR/experiment.log"
fi

wait $STRESS_PID 2>/dev/null
echo "stress-ng done." | tee -a "$OUT_DIR/experiment.log"

# PSI after stress
echo "--- PSI AFTER stress ---" | tee -a "$OUT_DIR/experiment.log"
cat /proc/pressure/memory | tee -a "$OUT_DIR/experiment.log"
cat /proc/pressure/io     | tee -a "$OUT_DIR/experiment.log"

# Final oom_score
echo "--- oom_score AFTER stress ---" | tee -a "$OUT_DIR/experiment.log"
cat /proc/$SERVER_PID/oom_score     2>/dev/null | tee -a "$OUT_DIR/experiment.log" || echo "Server gone"
cat /proc/$SERVER_PID/oom_score_adj 2>/dev/null | tee -a "$OUT_DIR/experiment.log"

# Check results files
echo "--- Files generated ---" | tee -a "$OUT_DIR/experiment.log"
ls -la "$OUT_DIR/" | tee -a "$OUT_DIR/experiment.log"

kill $METRICS_PID 2>/dev/null
kill $SERVER_PID  2>/dev/null
sudo rmdir "$CGROUP" 2>/dev/null

echo "End time: $(date)" | tee -a "$OUT_DIR/experiment.log"
echo "========================================"
echo " EXPERIMENT 1 COMPLETE"
echo "========================================"
