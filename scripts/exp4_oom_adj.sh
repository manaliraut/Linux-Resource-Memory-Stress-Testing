#!/bin/bash
# Experiment 4: oom_score_adj - FIXED VERSION
# Uses 200MB limit to guarantee OOM kill for victim selection validation

EXP_DIR=/home/durgaaishwarya/os_project/results/exp4_oom_adj
TRIAL=${1:-1}
OUT_DIR="$EXP_DIR/trial_$TRIAL"
mkdir -p "$OUT_DIR"
CGROUP=/sys/fs/cgroup/os_exp4

echo "========================================" | tee "$OUT_DIR/experiment.log"
echo " EXPERIMENT 4: oom_score_adj Trial $TRIAL" | tee -a "$OUT_DIR/experiment.log"
echo "========================================" | tee -a "$OUT_DIR/experiment.log"
echo "Start: $(date)" | tee -a "$OUT_DIR/experiment.log"

sudo rmdir "$CGROUP" 2>/dev/null
sudo mkdir -p "$CGROUP"
echo "209715200" | sudo tee "$CGROUP/memory.max"
echo "0"         | sudo tee "$CGROUP/memory.swap.max"
echo "memory.max=200MB swap=disabled" | tee -a "$OUT_DIR/experiment.log"

/home/durgaaishwarya/os_project/scripts/collect_metrics.sh "$OUT_DIR" "$CGROUP" &
METRICS_PID=$!

taskset -c 0 python3 /home/durgaaishwarya/os_project/scripts/server.py &
SERVER_PID=$!
sleep 2
echo $SERVER_PID | sudo tee "$CGROUP/cgroup.procs"
sudo bash -c "echo -500 > /proc/$SERVER_PID/oom_score_adj"
echo "HTTP server PID=$SERVER_PID oom_score_adj=-500 (protected)" | tee -a "$OUT_DIR/experiment.log"

python3 -c "
import time, os
data = bytearray(150 * 1024 * 1024)
print(f'Victim PID={os.getpid()} allocated 150MB', flush=True)
time.sleep(300)
" &
VICTIM_PID=$!
sleep 1
echo $VICTIM_PID | sudo tee -a "$CGROUP/cgroup.procs"
sudo bash -c "echo 500 > /proc/$VICTIM_PID/oom_score_adj"
echo "Victim PID=$VICTIM_PID oom_score_adj=+500 (target)" | tee -a "$OUT_DIR/experiment.log"

echo "--- oom_scores BEFORE stress ---" | tee -a "$OUT_DIR/experiment.log"
echo "Server  oom_score: $(cat /proc/$SERVER_PID/oom_score 2>/dev/null)" | tee -a "$OUT_DIR/experiment.log"
echo "Victim  oom_score: $(cat /proc/$VICTIM_PID/oom_score 2>/dev/null)"  | tee -a "$OUT_DIR/experiment.log"
echo "Server  oom_score_adj: $(cat /proc/$SERVER_PID/oom_score_adj 2>/dev/null)" | tee -a "$OUT_DIR/experiment.log"
echo "Victim  oom_score_adj: $(cat /proc/$VICTIM_PID/oom_score_adj 2>/dev/null)"  | tee -a "$OUT_DIR/experiment.log"

echo "server_pid,server_oom_score,server_oom_adj,victim_pid,victim_oom_score,victim_oom_adj" \
    > "$OUT_DIR/oom_scores.csv"
echo "$SERVER_PID,$(cat /proc/$SERVER_PID/oom_score 2>/dev/null),$(cat /proc/$SERVER_PID/oom_score_adj 2>/dev/null),$VICTIM_PID,$(cat /proc/$VICTIM_PID/oom_score 2>/dev/null),$(cat /proc/$VICTIM_PID/oom_score_adj 2>/dev/null)" \
    >> "$OUT_DIR/oom_scores.csv"

taskset -c 1 wrk -t2 -c10 -d15s --latency http://localhost:8080/ > "$OUT_DIR/wrk_baseline.txt" 2>&1
cat "$OUT_DIR/wrk_baseline.txt" | tee -a "$OUT_DIR/experiment.log"

echo "--- Launching memory hog to trigger OOM ---" | tee -a "$OUT_DIR/experiment.log"
sudo bash -c "echo \$\$ > $CGROUP/cgroup.procs; python3 -c \"
import time, os
chunks = []
print(f'Hog PID={os.getpid()} starting', flush=True)
for i in range(20):
    chunks.append(bytearray(10 * 1024 * 1024))
    print(f'Hog allocated {(i+1)*10}MB', flush=True)
    time.sleep(0.3)
time.sleep(60)
\"" &
HOG_PID=$!

echo "--- Monitoring for OOM kill ---" | tee -a "$OUT_DIR/experiment.log"
for i in $(seq 1 30); do
    sleep 2
    OOM_COUNT=$(grep "^oom_kill" "$CGROUP/memory.events" 2>/dev/null | awk '{print $2}' || echo 0)
    MEM_MB=$(( $(cat "$CGROUP/memory.current" 2>/dev/null || echo 0) / 1024 / 1024 ))
    echo "t=$((i*2))s mem=${MEM_MB}MB oom_kill=$OOM_COUNT" | tee -a "$OUT_DIR/experiment.log"
    if [ "$OOM_COUNT" -gt "0" ]; then
        echo "*** OOM KILL DETECTED at t=$((i*2))s ***" | tee -a "$OUT_DIR/experiment.log"
        break
    fi
done

echo "--- Process survival check ---" | tee -a "$OUT_DIR/experiment.log"
if kill -0 $SERVER_PID 2>/dev/null; then
    echo "HTTP server SURVIVED (PID=$SERVER_PID) - H3 SUPPORTED" | tee -a "$OUT_DIR/experiment.log"
else
    echo "HTTP server KILLED (PID=$SERVER_PID) - H3 REJECTED" | tee -a "$OUT_DIR/experiment.log"
fi
if kill -0 $VICTIM_PID 2>/dev/null; then
    echo "Victim process SURVIVED (PID=$VICTIM_PID) - checking..." | tee -a "$OUT_DIR/experiment.log"
else
    echo "Victim process KILLED (PID=$VICTIM_PID) - H3 SUPPORTED" | tee -a "$OUT_DIR/experiment.log"
fi

taskset -c 1 wrk -t2 -c10 -d15s --latency http://localhost:8080/ > "$OUT_DIR/wrk_after_oom.txt" 2>&1

echo "--- Final memory.events ---" | tee -a "$OUT_DIR/experiment.log"
cat "$CGROUP/memory.events" | tee "$OUT_DIR/memory_events_after.txt" | tee -a "$OUT_DIR/experiment.log"

echo "--- dmesg OOM entries ---" | tee -a "$OUT_DIR/experiment.log"
sudo dmesg | grep -i "oom\|killed process\|out of memory" | tail -20 \
    | tee "$OUT_DIR/dmesg_oom.txt" | tee -a "$OUT_DIR/experiment.log"

cat /proc/pressure/memory | tee -a "$OUT_DIR/experiment.log"

kill $METRICS_PID 2>/dev/null
kill $SERVER_PID  2>/dev/null
kill $VICTIM_PID  2>/dev/null
kill $HOG_PID     2>/dev/null
sudo rmdir "$CGROUP" 2>/dev/null

echo "End: $(date)" | tee -a "$OUT_DIR/experiment.log"
echo "========================================"
echo " EXPERIMENT 4 COMPLETE"
echo "========================================"
