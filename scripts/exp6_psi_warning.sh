#!/bin/bash
# Experiment 6: PSI Early Warning System
# Hypothesis H2: PSI some avg10 > 15% for 10s predicts OOM within 30s

EXP_DIR=/home/durgaaishwarya/os_project/results/exp6_psi_warning
TRIAL=${1:-1}
OUT_DIR="$EXP_DIR/trial_$TRIAL"
mkdir -p "$OUT_DIR"
CGROUP=/sys/fs/cgroup/os_exp6

echo "========================================" | tee "$OUT_DIR/experiment.log"
echo " EXPERIMENT 6: PSI WARNING Trial $TRIAL"  | tee -a "$OUT_DIR/experiment.log"
echo "========================================" | tee -a "$OUT_DIR/experiment.log"
echo "Start: $(date)" | tee -a "$OUT_DIR/experiment.log"
echo "Threshold: PSI some avg10 > 15% for 10 consecutive seconds" | tee -a "$OUT_DIR/experiment.log"

sudo mkdir -p "$CGROUP"
echo "209715200" | sudo tee "$CGROUP/memory.max"
echo "max"       | sudo tee "$CGROUP/memory.swap.max"

/home/durgaaishwarya/os_project/scripts/collect_metrics.sh "$OUT_DIR" "$CGROUP" &
METRICS_PID=$!

taskset -c 0 python3 /home/durgaaishwarya/os_project/scripts/server.py &
SERVER_PID=$!
echo $SERVER_PID | sudo tee "$CGROUP/cgroup.procs"
sleep 2

# Capture baseline p95 latency
taskset -c 1 wrk -t2 -c10 -d20s --latency http://localhost:8080/ > "$OUT_DIR/wrk_baseline.txt" 2>&1
BASELINE_P95=$(grep "99%" "$OUT_DIR/wrk_baseline.txt" | awk '{print $2}' || echo "0")
echo "Baseline p95 latency: $BASELINE_P95" | tee -a "$OUT_DIR/experiment.log"

sudo bash -c "echo \$\$ > $CGROUP/cgroup.procs && stress-ng --vm 1 --vm-bytes 90% --vm-keep --timeout 120s" &
STRESS_PID=$!

# PSI threshold monitoring loop - core of H2
echo "timestamp,psi_some_avg10,threshold_hit,consecutive_count,warning_issued,oom_count" \
    > "$OUT_DIR/psi_warning_log.csv"

CONSECUTIVE=0
WARNING_ISSUED=0
WARNING_TIME=0
PSI_THRESHOLD=15.0

echo "--- Monitoring PSI threshold ---" | tee -a "$OUT_DIR/experiment.log"

for i in $(seq 1 120); do
    sleep 1
    TS=$(date +%s)
    PSI_VAL=$(cat /proc/pressure/memory | grep "^some" | awk '{print $2}' | cut -d= -f2)
    OOM_COUNT=$(grep "^oom_kill" "$CGROUP/memory.events" 2>/dev/null | awk '{print $2}' || echo 0)

    # Check if PSI exceeds threshold
    EXCEEDS=$(echo "$PSI_VAL > $PSI_THRESHOLD" | bc -l 2>/dev/null || echo 0)
    if [ "$EXCEEDS" = "1" ]; then
        CONSECUTIVE=$((CONSECUTIVE + 1))
    else
        CONSECUTIVE=0
    fi

    # Issue warning if threshold held for 10 consecutive seconds
    if [ "$CONSECUTIVE" -ge 10 ] && [ "$WARNING_ISSUED" = "0" ]; then
        WARNING_ISSUED=1
        WARNING_TIME=$TS
        echo "*** PSI WARNING ISSUED at $(date) ***" | tee -a "$OUT_DIR/experiment.log"
        echo "PSI avg10=$PSI_VAL exceeded 15% for 10 consecutive seconds" | tee -a "$OUT_DIR/experiment.log"
        echo "Now watching for OOM or latency spike within 30 seconds..." | tee -a "$OUT_DIR/experiment.log"
        # Take latency snapshot immediately at warning
        taskset -c 1 wrk -t2 -c10 -d10s --latency http://localhost:8080/ \
            > "$OUT_DIR/wrk_at_warning.txt" 2>&1
    fi

    echo "$TS,$PSI_VAL,$EXCEEDS,$CONSECUTIVE,$WARNING_ISSUED,$OOM_COUNT" \
        >> "$OUT_DIR/psi_warning_log.csv"

    # If warning issued, check for OOM within 30s
    if [ "$WARNING_ISSUED" = "1" ]; then
        ELAPSED=$((TS - WARNING_TIME))
        if [ "$OOM_COUNT" -gt "0" ]; then
            echo "OOM occurred $ELAPSED seconds after PSI warning - H2 SUPPORTED" \
                | tee -a "$OUT_DIR/experiment.log"
            break
        fi
        if [ "$ELAPSED" -ge 30 ]; then
            echo "30s elapsed after warning - checking latency..." | tee -a "$OUT_DIR/experiment.log"
            taskset -c 1 wrk -t2 -c10 -d10s --latency http://localhost:8080/ \
                > "$OUT_DIR/wrk_30s_after_warning.txt" 2>&1
            break
        fi
    fi
done

cat "$CGROUP/memory.events" | tee "$OUT_DIR/memory_events_after.txt"
sudo dmesg | grep -i "oom\|killed process" | tail -10 | tee "$OUT_DIR/dmesg_oom.txt"
cat /proc/pressure/memory | tee -a "$OUT_DIR/experiment.log"

wait $STRESS_PID 2>/dev/null
kill $METRICS_PID 2>/dev/null
kill $SERVER_PID  2>/dev/null
sudo rmdir "$CGROUP" 2>/dev/null

echo "End: $(date)" | tee -a "$OUT_DIR/experiment.log"
echo " EXPERIMENT 6 COMPLETE"
