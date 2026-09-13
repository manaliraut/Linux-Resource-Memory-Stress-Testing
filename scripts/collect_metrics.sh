#!/bin/bash
# Metric Collection Script - UPDATED WITH IOSTAT + CPU PINNING SUPPORT
# Samples: PSI, /proc/meminfo, vmstat, cgroup memory, iostat, oom_score
# Interval: 1 second

OUTPUT_DIR=$1
CGROUP_PATH=$2

if [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <output_dir> [cgroup_path]"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Write headers
echo "timestamp,mem_some_avg10,mem_some_avg60,mem_full_avg10,mem_full_avg60,io_some_avg10,cpu_some_avg10" \
    > "$OUTPUT_DIR/psi.csv"

echo "timestamp,MemTotal,MemFree,MemAvailable,Buffers,Cached,SwapTotal,SwapFree,SwapUsed" \
    > "$OUTPUT_DIR/meminfo.csv"

echo "timestamp,r,b,swpd,free,buff,cache,si,so,bi,bo,in,cs,us,sy,id,wa" \
    > "$OUTPUT_DIR/vmstat.csv"

echo "timestamp,cgroup_current,cgroup_anon,cgroup_file,pgfault,pgmajfault,oom_kill" \
    > "$OUTPUT_DIR/cgroup.csv"

echo "timestamp,device,tps,kb_read_per_s,kb_write_per_s,kb_read,kb_write" \
    > "$OUTPUT_DIR/iostat.csv"

echo "timestamp,MemTotal_kb,MemFree_kb,MemAvailable_kb,SwapUsed_kb,MemUsed_kb" \
    > "$OUTPUT_DIR/memory_usage.csv"

echo "Metric collection started. Output: $OUTPUT_DIR"
echo "Press Ctrl+C to stop."

while true; do
    TS=$(date +%s)

    # --- PSI ---
    MEM_PSI=$(cat /proc/pressure/memory 2>/dev/null)
    IO_PSI=$(cat /proc/pressure/io 2>/dev/null)
    CPU_PSI=$(cat /proc/pressure/cpu 2>/dev/null)
    MEM_SOME_10=$(echo "$MEM_PSI" | grep "^some" | awk '{print $2}' | cut -d= -f2)
    MEM_SOME_60=$(echo "$MEM_PSI" | grep "^some" | awk '{print $3}' | cut -d= -f2)
    MEM_FULL_10=$(echo "$MEM_PSI" | grep "^full" | awk '{print $2}' | cut -d= -f2)
    MEM_FULL_60=$(echo "$MEM_PSI" | grep "^full" | awk '{print $3}' | cut -d= -f2)
    IO_SOME_10=$(echo "$IO_PSI"   | grep "^some" | awk '{print $2}' | cut -d= -f2)
    CPU_SOME_10=$(echo "$CPU_PSI" | grep "^some" | awk '{print $2}' | cut -d= -f2)
    echo "$TS,$MEM_SOME_10,$MEM_SOME_60,$MEM_FULL_10,$MEM_FULL_60,$IO_SOME_10,$CPU_SOME_10" \
        >> "$OUTPUT_DIR/psi.csv"

    # --- /proc/meminfo ---
    MEM_TOTAL=$(grep "^MemTotal"     /proc/meminfo | awk '{print $2}')
    MEM_FREE=$(grep  "^MemFree"      /proc/meminfo | awk '{print $2}')
    MEM_AVAIL=$(grep "^MemAvailable" /proc/meminfo | awk '{print $2}')
    BUFFERS=$(grep   "^Buffers"      /proc/meminfo | awk '{print $2}')
    CACHED=$(grep    "^Cached:"      /proc/meminfo | awk '{print $2}')
    SWAP_TOTAL=$(grep "^SwapTotal"   /proc/meminfo | awk '{print $2}')
    SWAP_FREE=$(grep  "^SwapFree"    /proc/meminfo | awk '{print $2}')
    SWAP_USED=$((SWAP_TOTAL - SWAP_FREE))
    echo "$TS,$MEM_TOTAL,$MEM_FREE,$MEM_AVAIL,$BUFFERS,$CACHED,$SWAP_TOTAL,$SWAP_FREE,$SWAP_USED" \
        >> "$OUTPUT_DIR/meminfo.csv"

    # --- Memory Usage (for dedicated memory usage plot) ---
    MEM_USED=$((MEM_TOTAL - MEM_FREE - BUFFERS - CACHED))
    echo "$TS,$MEM_TOTAL,$MEM_FREE,$MEM_AVAIL,$SWAP_USED,$MEM_USED" \
        >> "$OUTPUT_DIR/memory_usage.csv"

    # --- vmstat ---
    VMSTAT=$(vmstat 1 1 | tail -1)
    echo "$TS,$VMSTAT" >> "$OUTPUT_DIR/vmstat.csv"

    # --- iostat (NEW) ---
    IOSTAT=$(iostat -d -k 1 1 2>/dev/null | grep -v "^$\|^Linux\|^Device" | head -3)
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            DEVICE=$(echo "$line" | awk '{print $1}')
            TPS=$(echo "$line"    | awk '{print $2}')
            KB_RS=$(echo "$line"  | awk '{print $3}')
            KB_WS=$(echo "$line"  | awk '{print $4}')
            KB_R=$(echo "$line"   | awk '{print $5}')
            KB_W=$(echo "$line"   | awk '{print $6}')
            echo "$TS,$DEVICE,$TPS,$KB_RS,$KB_WS,$KB_R,$KB_W" \
                >> "$OUTPUT_DIR/iostat.csv"
        fi
    done <<< "$IOSTAT"

    # --- cgroup metrics ---
    if [ -n "$CGROUP_PATH" ] && [ -d "$CGROUP_PATH" ]; then
        CG_CURRENT=$(cat "$CGROUP_PATH/memory.current"    2>/dev/null || echo 0)
        CG_ANON=$(grep "^anon "      "$CGROUP_PATH/memory.stat" 2>/dev/null | awk '{print $2}' || echo 0)
        CG_FILE=$(grep "^file "      "$CGROUP_PATH/memory.stat" 2>/dev/null | awk '{print $2}' || echo 0)
        PGFAULT=$(grep "^pgfault "   "$CGROUP_PATH/memory.stat" 2>/dev/null | awk '{print $2}' || echo 0)
        PGMAJ=$(grep "^pgmajfault "  "$CGROUP_PATH/memory.stat" 2>/dev/null | awk '{print $2}' || echo 0)
        OOM_KILL=$(grep "^oom_kill " "$CGROUP_PATH/memory.events" 2>/dev/null | awk '{print $2}' || echo 0)
        echo "$TS,$CG_CURRENT,$CG_ANON,$CG_FILE,$PGFAULT,$PGMAJ,$OOM_KILL" \
            >> "$OUTPUT_DIR/cgroup.csv"
    fi

    # --- dmesg OOM check ---
    dmesg --time-format iso 2>/dev/null | grep -i "oom\|killed process" | tail -5 \
        >> "$OUTPUT_DIR/dmesg_oom.log" 2>/dev/null

    sleep 1
done
