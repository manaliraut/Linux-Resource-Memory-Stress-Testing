#!/bin/bash
# Experiment 3: memory.high + memory.max
# Hypothesis H1: memory.high causes PSI throttling BEFORE OOM

EXP_DIR=/home/durgaaishwarya/os_project/results/exp3_high_max
TRIAL=${1:-1}
OUT_DIR="$EXP_DIR/trial_$TRIAL"
mkdir -p "$OUT_DIR"
CGROUP=/sys/fs/cgroup/os_exp3

echo "========================================" | tee "$OUT_DIR/experiment.log"
echo " EXPERIMENT 3: memory.high+max Trial $TRIAL" | tee -a "$OUT_DIR/experiment.log"
echo "========================================" | tee -a "$OUT_DIR/experiment.log"
echo "Start: $(date)" | tee -a "$OUT_DIR/experiment.log"

# Setup cgroup: high=200MB, max=350MB
sudo mkdir -p "$CGROUP"
echo "209715200" | sudo tee "$CGROUP/memory.high"   # 200MB
echo "367001600" | sudo tee "$CGROUP/memory.max"    # 350MB
echo "max"       | sudo tee "$CGROUP/memory.swap.max"
echo "memory.high=200MB, memory.max=350MB" | tee -a "$OUT_DIR/experiment.log"

cat "$CGROUP/memory.events" | tee "$OUT_DIR/memory_events_before.txt"

/home/durgaaishwarya/os_project/scripts/collect_metrics.sh "$OUT_DIR" "$CGROUP" &
METRICS_PID=$!

taskset -c 0 python3 /home/durgaaishwarya/os_project/scripts/server.py &
SERVER_PID=$!
echo $SERVER_PID | sudo tee "$CGROUP/cgroup.procs"
sleep 2

# Baseline
taskset -c 1 wrk -t2 -c10 -d20s --latency http://localhost:8080/ > "$OUT_DIR/wrk_baseline.txt" 2>&1
cat "$OUT_DIR/wrk_baseline.txt" | tee -a "$OUT_DIR/experiment.log"

# Stress - will hit memory.high first (throttling), then memory.max (OOM)
echo "--- Starting memory hog ---" | tee -a "$OUT_DIR/experiment.log"
sudo bash -c "echo \$\$ > $CGROUP/cgroup.procs && stress-ng --vm 1 --vm-bytes 90% --vm-keep --timeout 90s" &
STRESS_PID=$!

# Capture at 10s intervals to observe throttling progression
for i in 1 2 3; do
    sleep 10
    echo "=== Snapshot at ${i}0s ===" | tee -a "$OUT_DIR/experiment.log"
    cat /proc/pressure/memory | tee -a "$OUT_DIR/experiment.log"
    cat "$CGROUP/memory.events" 2>/dev/null | tee -a "$OUT_DIR/experiment.log"
    taskset -c 1 wrk -t2 -c10 -d10s --latency http://localhost:8080/ \
        >> "$OUT_DIR/wrk_snapshots.txt" 2>&1
done

wait $STRESS_PID 2>/dev/null

echo "--- Final memory.events ---" | tee -a "$OUT_DIR/experiment.log"
cat "$CGROUP/memory.events" | tee "$OUT_DIR/memory_events_after.txt" | tee -a "$OUT_DIR/experiment.log"

sudo dmesg | grep -i "oom\|killed process\|memory cgroup" | tail -20 \
    | tee "$OUT_DIR/dmesg_oom.txt"

kill $METRICS_PID 2>/dev/null
kill $SERVER_PID  2>/dev/null
sudo rmdir "$CGROUP" 2>/dev/null

echo "End: $(date)" | tee -a "$OUT_DIR/experiment.log"
echo " EXPERIMENT 3 COMPLETE"
