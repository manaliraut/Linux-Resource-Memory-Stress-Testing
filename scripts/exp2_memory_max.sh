#!/bin/bash
# Experiment 2: memory.max - Trigger deterministic memcg OOM
# Fixed: tighter memory limit to guarantee OOM kill

EXP_DIR=/home/durgaaishwarya/os_project/results/exp2_memory_max
TRIAL=${1:-1}
OUT_DIR="$EXP_DIR/trial_$TRIAL"
mkdir -p "$OUT_DIR"
CGROUP=/sys/fs/cgroup/os_exp2

echo "========================================" | tee "$OUT_DIR/experiment.log"
echo " EXPERIMENT 2: memory.max - Trial $TRIAL" | tee -a "$OUT_DIR/experiment.log"
echo "========================================" | tee -a "$OUT_DIR/experiment.log"
echo "Start: $(date)" | tee -a "$OUT_DIR/experiment.log"

# Cleanup any leftover cgroup
sudo rmdir "$CGROUP" 2>/dev/null
sudo mkdir -p "$CGROUP"

# Set tight limit: 200MB max, NO swap
echo "209715200" | sudo tee "$CGROUP/memory.max"    # 200MB
echo "0"         | sudo tee "$CGROUP/memory.swap.max"
echo "memory.max=200MB, swap=disabled" | tee -a "$OUT_DIR/experiment.log"

# Record initial memory.events
cat "$CGROUP/memory.events" | tee "$OUT_DIR/memory_events_before.txt"

# Start metric collection
/home/durgaaishwarya/os_project/scripts/collect_metrics.sh "$OUT_DIR" "$CGROUP" &
METRICS_PID=$!

# Start HTTP server and add to cgroup
taskset -c 0 python3 /home/durgaaishwarya/os_project/scripts/server.py &
SERVER_PID=$!
sleep 2
echo $SERVER_PID | sudo tee "$CGROUP/cgroup.procs"
echo "Server PID=$SERVER_PID added to cgroup" | tee -a "$OUT_DIR/experiment.log"

# Verify server is up
if ! curl -s http://localhost:8080/ > /dev/null; then
    echo "ERROR: Server not responding" | tee -a "$OUT_DIR/experiment.log"
fi

# Baseline latency
echo "--- Baseline latency ---" | tee -a "$OUT_DIR/experiment.log"
taskset -c 1 wrk -t2 -c10 -d20s --latency http://localhost:8080/ > "$OUT_DIR/wrk_baseline.txt" 2>&1
cat "$OUT_DIR/wrk_baseline.txt" | tee -a "$OUT_DIR/experiment.log"

# Launch memory hog INSIDE cgroup - allocate 500MB to force OOM
echo "--- Launching memory hog (500MB inside 200MB cgroup) ---" | tee -a "$OUT_DIR/experiment.log"
sudo bash -c "echo \$\$ > $CGROUP/cgroup.procs; exec python3 -c \"
import time, os
print(f'Memory hog PID={os.getpid()}', flush=True)
chunks = []
for i in range(50):
    chunks.append(bytearray(10 * 1024 * 1024))  # 10MB per chunk
    print(f'Allocated {(i+1)*10}MB', flush=True)
    time.sleep(0.2)
time.sleep(60)
\"" &
HOG_PID=$!
echo "Memory hog PID=$HOG_PID" | tee -a "$OUT_DIR/experiment.log"

# Monitor for OOM kill - check every 2 seconds for 60 seconds
echo "--- Monitoring for OOM kill ---" | tee -a "$OUT_DIR/experiment.log"
for i in $(seq 1 30); do
    sleep 2
    OOM_COUNT=$(grep "^oom_kill" "$CGROUP/memory.events" 2>/dev/null | awk '{print $2}' || echo 0)
    MEM_CURRENT=$(cat "$CGROUP/memory.current" 2>/dev/null || echo 0)
    MEM_MB=$((MEM_CURRENT / 1024 / 1024))
    echo "t=${i}x2s: cgroup_mem=${MEM_MB}MB oom_kill=$OOM_COUNT" | tee -a "$OUT_DIR/experiment.log"
    if [ "$OOM_COUNT" -gt "0" ]; then
        echo "*** OOM KILL DETECTED at t=$((i*2))s ***" | tee -a "$OUT_DIR/experiment.log"
        break
    fi
done

# Measure latency after OOM
echo "--- Latency after OOM event ---" | tee -a "$OUT_DIR/experiment.log"
taskset -c 1 wrk -t2 -c10 -d15s --latency http://localhost:8080/ > "$OUT_DIR/wrk_after_oom.txt" 2>&1
cat "$OUT_DIR/wrk_after_oom.txt" | tee -a "$OUT_DIR/experiment.log"

# Final memory.events
echo "--- Final memory.events ---" | tee -a "$OUT_DIR/experiment.log"
cat "$CGROUP/memory.events" | tee "$OUT_DIR/memory_events_after.txt" | tee -a "$OUT_DIR/experiment.log"

# dmesg OOM entries
echo "--- dmesg OOM entries ---" | tee -a "$OUT_DIR/experiment.log"
sudo dmesg | grep -i "oom\|killed process\|memory cgroup\|out of memory" | tail -20 \
    | tee "$OUT_DIR/dmesg_oom.txt" | tee -a "$OUT_DIR/experiment.log"

# PSI snapshot
echo "--- PSI at end ---" | tee -a "$OUT_DIR/experiment.log"
cat /proc/pressure/memory | tee -a "$OUT_DIR/experiment.log"

# Cleanup
kill $METRICS_PID 2>/dev/null
kill $SERVER_PID  2>/dev/null
kill $HOG_PID     2>/dev/null
sudo rmdir "$CGROUP" 2>/dev/null

echo "End: $(date)" | tee -a "$OUT_DIR/experiment.log"
echo "========================================"
echo " EXPERIMENT 2 COMPLETE"
echo "========================================"
