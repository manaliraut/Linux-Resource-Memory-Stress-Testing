#!/bin/bash
# Experiment 5: Swap enabled vs disabled
# Hypothesis H4: swap increases time-to-OOM but increases I/O PSI

EXP_DIR=/home/durgaaishwarya/os_project/results/exp5_swap
TRIAL=${1:-1}
MODE=${2:-"swap_on"}   # swap_on or swap_off
OUT_DIR="$EXP_DIR/${MODE}_trial_$TRIAL"
mkdir -p "$OUT_DIR"
CGROUP=/sys/fs/cgroup/os_exp5

echo "========================================" | tee "$OUT_DIR/experiment.log"
echo " EXPERIMENT 5: SWAP $MODE - Trial $TRIAL" | tee -a "$OUT_DIR/experiment.log"
echo "========================================" | tee -a "$OUT_DIR/experiment.log"
echo "Start: $(date)" | tee -a "$OUT_DIR/experiment.log"

sudo mkdir -p "$CGROUP"
echo "367001600" | sudo tee "$CGROUP/memory.max"   # 350MB

# Configure swap based on mode
if [ "$MODE" = "swap_off" ]; then
    echo "0"   | sudo tee "$CGROUP/memory.swap.max"
    echo "Swap DISABLED for this cgroup" | tee -a "$OUT_DIR/experiment.log"
else
    echo "max" | sudo tee "$CGROUP/memory.swap.max"
    echo "Swap ENABLED for this cgroup" | tee -a "$OUT_DIR/experiment.log"
fi

# Record swap state
free -h | tee "$OUT_DIR/swap_state.txt" | tee -a "$OUT_DIR/experiment.log"
cat /proc/pressure/io | tee -a "$OUT_DIR/experiment.log"

/home/durgaaishwarya/os_project/scripts/collect_metrics.sh "$OUT_DIR" "$CGROUP" &
METRICS_PID=$!

taskset -c 0 python3 /home/durgaaishwarya/os_project/scripts/server.py &
SERVER_PID=$!
echo $SERVER_PID | sudo tee "$CGROUP/cgroup.procs"
sleep 2

taskset -c 1 wrk -t2 -c10 -d20s --latency http://localhost:8080/ > "$OUT_DIR/wrk_baseline.txt" 2>&1
cat "$OUT_DIR/wrk_baseline.txt" | tee -a "$OUT_DIR/experiment.log"

# Record OOM start time
OOM_START=$(date +%s)
echo "Memory stress start: $OOM_START" | tee -a "$OUT_DIR/experiment.log"

sudo bash -c "echo \$\$ > $CGROUP/cgroup.procs && stress-ng --vm 1 --vm-bytes 90% --vm-keep --timeout 120s" &
STRESS_PID=$!

# Sample I/O PSI every 5 seconds until OOM or timeout
for i in $(seq 1 20); do
    sleep 5
    TS=$(date +%s)
    IO_PSI=$(cat /proc/pressure/io | grep "^some" | awk '{print $2}' | cut -d= -f2)
    MEM_PSI=$(cat /proc/pressure/memory | grep "^some" | awk '{print $2}' | cut -d= -f2)
    OOM_COUNT=$(grep "^oom_kill" "$CGROUP/memory.events" 2>/dev/null | awk '{print $2}' || echo 0)
    echo "$TS,io_psi=$IO_PSI,mem_psi=$MEM_PSI,oom_kill=$OOM_COUNT" \
        | tee -a "$OUT_DIR/io_psi_timeline.csv"
    if [ "$OOM_COUNT" -gt "0" ] 2>/dev/null; then
        OOM_END=$(date +%s)
        echo "OOM occurred at: $OOM_END" | tee -a "$OUT_DIR/experiment.log"
        echo "Time-to-OOM: $((OOM_END - OOM_START)) seconds" | tee -a "$OUT_DIR/experiment.log"
        break
    fi
done

taskset -c 1 wrk -t2 -c10 -d20s --latency http://localhost:8080/ > "$OUT_DIR/wrk_after.txt" 2>&1

echo "--- Final I/O PSI ---" | tee -a "$OUT_DIR/experiment.log"
cat /proc/pressure/io | tee -a "$OUT_DIR/experiment.log"
cat "$CGROUP/memory.events" | tee "$OUT_DIR/memory_events_after.txt"
sudo dmesg | grep -i "oom\|killed process" | tail -10 | tee "$OUT_DIR/dmesg_oom.txt"

wait $STRESS_PID 2>/dev/null
kill $METRICS_PID 2>/dev/null
kill $SERVER_PID  2>/dev/null
sudo rmdir "$CGROUP" 2>/dev/null

echo "End: $(date)" | tee -a "$OUT_DIR/experiment.log"
echo " EXPERIMENT 5 COMPLETE - MODE: $MODE"
