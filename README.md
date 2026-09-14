# Experimental Analysis of Linux Memory Pressure, cgroup v2 Limits, and OOM Killer Decisions



| Experiment 1 | Experiment 2 | Experiment 3 |
|-------------|-------------|-------------|
| <img src="https://github.com/user-attachments/assets/d889395a-ec3a-43cb-b874-9b2af632c9f2" width="250"> | <img src="https://github.com/user-attachments/assets/940a05eb-065e-4633-b602-1529b00ebd7a" width="250"> | <img src="https://github.com/user-attachments/assets/e7df6757-d2d8-4089-9d90-060991ab2695" width="250"> |
| Baseline | memory.max OOM | memory.high Throttling |
| No memory limits applied. | Hard memory limit of 200 MB with swap disabled. | Soft limit at 200 MB and hard limit at 350 MB.|
|No memory limits at all. stress-ng uses 50% of RAM. This gives us a reference point — what does normal look like? PSI was 0% the entire time.|We set a hard 200 MB limit with swap off. The goal: reliably trigger a deterministic OOM kill. No escape hatch.|Soft limit at 200 MB, hard cap at 350 MB. The kernel has room to throttle before killing anything. We want to see thousands of throttle events with zero kills.|

| Experiment 4 | Experiment 5 | Experiment 6 |
|-------------|-------------|-------------|
| <img src="https://github.com/user-attachments/assets/cc5282b1-3571-4ef9-98fe-487744406e32" width="250"> | <img src="https://github.com/user-attachments/assets/3913a3ad-d88a-46f6-a6d1-3e980ad23ee6" width="250"> | <img src="https://github.com/user-attachments/assets/ff315806-6f15-4eee-94b1-723fa76bc9a3" width="250"> |
| OOM Victim Selection | Swap ON vs OFF | PSI Early Warning |
| Manipulated `oom_score_adj` values to study kill behavior. | Compared system behavior under identical memory constraints.| Evaluated PSI's effectiveness in predicting latency spikes before failure.|
|We gave the HTTP server oom_score_adj = -500 (protect it) and a separate victim process oom_score_adj = +500 (kill it first). Does the kernel obey?|Same memory limit, but in one case swap is enabled and in the other it's disabled. How different is time-to-OOM? And what happens to disk I/O?|Can we detect impending failure before it happens? We monitor PSI and fire a warning when it crosses 15% for 10 consecutive seconds, then watch what happens next.|

### H1: Hard vs Soft Memory Limits
- `memory.max` causes immediate OOM termination.
- `memory.high` triggers throttling while avoiding process termination.

### H2: PSI as an Early Warning Signal
- PSI `avg10 > 15%` for 10 seconds predicts significant latency degradation within 30 seconds.

### H3: Deterministic Victim Selection
- The process with the highest `oom_score_adj` is consistently selected as the OOM victim.

### H4: Swap is a Tradeoff
- Swap prevents OOM kills but introduces additional I/O stalls.

---
## Objectives

We aimed to answer the following questions:

- When exactly does Linux transition from memory pressure to OOM conditions?
- How do `memory.max` and `memory.high` affect application behavior?
- Can PSI (Pressure Stall Information) predict failures before they happen?
- Can `oom_score_adj` reliably control OOM victim selection?
- Does swap improve survivability under memory pressure?

## Experimental Environment

| Component | Configuration |
|------------|--------------|
| OS | Ubuntu 24.04 LTS |
| Kernel | Linux 6.17 |
| Memory | 5.8 GB RAM |
| Virtualization | Oracle VirtualBox |
| Memory Control | cgroup v2 |
| Monitoring | PSI, vmstat, meminfo, iostat |
| Analysis Tools | Python, Pandas, Matplotlib |

---

## System Architecture

The framework consists of four major components:

### Workload Generation
- `stress-ng` memory stressor
- Python HTTP server
- `wrk` load generator

### Control Layer
- cgroup v2 configuration
- `memory.max`
- `memory.high`
- `memory.swap.max`

### Metrics Collection
- PSI metrics
- `/proc/meminfo`
- `memory.events`
- OOM scores
- `dmesg`
- I/O statistics

### Analysis Pipeline
- Automated CSV processing
- Statistical analysis
- Visualization generation
- Report creation

---

## Metrics Captured

- PSI (avg10, avg60, avg300)
- Memory utilization
- Available memory
- Swap usage
- OOM events
- OOM scores
- Latency (p50, p90, p99)
- Time-to-OOM
- I/O pressure statistics

---

## Key Findings

### H1 Validated
- `memory.max` resulted in deterministic OOM kills.
- `memory.high` produced thousands of throttle events with zero kills.

### H2 Validated
- PSI > 15% for 10 seconds accurately predicted latency degradation.
- Observed latency increases of up to 4176%.
- Zero false positives.

### H3 Validated
- `oom_score_adj` controlled victim selection in every trial.

### H4 Validated
- Swap prevented OOM kills.
- Maximum observed I/O PSI reached 49.31%.

---

## Practical Recommendations

- Use `memory.high` alongside `memory.max`.
- Continuously monitor PSI metrics.
- Configure `oom_score_adj` to protect critical services.
- Enable swap for resiliency, but monitor I/O pressure carefully.
