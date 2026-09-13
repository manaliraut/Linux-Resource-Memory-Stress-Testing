#!/usr/bin/env python3
"""
Analysis and Plot Generation Script
Generates all plots for the OS project report
"""
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np
import os
import glob

RESULTS = "/home/durgaaishwarya/os_project/results"
PLOTS   = "/home/durgaaishwarya/os_project/plots"
os.makedirs(PLOTS, exist_ok=True)

plt.rcParams.update({
    'figure.facecolor': 'white',
    'axes.facecolor':   'white',
    'axes.grid':        True,
    'grid.alpha':       0.3,
    'font.size':        11,
    'axes.titlesize':   13,
    'axes.labelsize':   11,
})

print("=" * 60)
print("  OS PROJECT - Plot Generation")
print("=" * 60)

# ── helper ──────────────────────────────────────────────────
def load_psi(path, divide_by_1000=False):
    try:
        df = pd.read_csv(path)
        df.columns = df.columns.str.strip()
        delta = df['timestamp'] - df['timestamp'].iloc[0]
        if divide_by_1000:
            delta = delta / 1000
        df['time_s'] = delta
        return df
    except Exception as e:
        print(f"  [warn] cannot load {path}: {e}")
        return None

def load_wrk(path):
    """Return dict with p50,p75,p90,p99 latency in ms."""
    out = {}
    try:
        with open(path) as f:
            for line in f:
                for pct in ['50%','75%','90%','99%']:
                    if pct in line:
                        val = line.split()[1]
                        mul = 1.0
                        if val.endswith('ms'): mul=1.0;   val=val[:-2]
                        elif val.endswith('us'): mul=0.001; val=val[:-2]
                        elif val.endswith('s') and not val.endswith('ms'):
                            mul=1000; val=val[:-1]
                        try: out[pct] = float(val)*mul
                        except: pass
    except: pass
    return out

# ════════════════════════════════════════════════════════════
# PLOT 1 – PSI comparison across experiments
# ════════════════════════════════════════════════════════════
print("\n[1/6] PSI comparison plot...")
fig, axes = plt.subplots(2, 3, figsize=(15, 8))
fig.suptitle('Memory PSI (some avg10) Across All Experiments', fontsize=14, fontweight='bold')

configs = [
    ('exp1_baseline',   'trial_2', 'Exp 1: Baseline',      '#2196F3'),
    ('exp2_memory_max', 'trial_1', 'Exp 2: memory.max',    '#F44336'),
    ('exp3_high_max',   'trial_1', 'Exp 3: memory.high+max','#FF9800'),
    ('exp4_oom_adj',    'trial_1', 'Exp 4: oom_score_adj', '#9C27B0'),
    ('exp5_swap',       'swap_off_trial_1','Exp 5: swap_off','#795548'),
    ('exp6_psi_warning','trial_1', 'Exp 6: PSI warning',   '#009688'),
]

for ax, (exp, trial, title, color) in zip(axes.flat, configs):
    psi_path = f"{RESULTS}/{exp}/{trial}/psi.csv"
    df = load_psi(psi_path, divide_by_1000=(exp == 'exp3_high_max'))
    if df is not None and 'mem_some_avg10' in df.columns:
        ax.plot(df['time_s'], df['mem_some_avg10'].astype(float),
                color=color, linewidth=1.5, label='some avg10')
        ax.fill_between(df['time_s'], df['mem_some_avg10'].astype(float),
                        alpha=0.15, color=color)
        if exp == 'exp6_psi_warning':
            ax.axhline(y=15, color='red', linestyle='--',
                       linewidth=1.2, label='15% threshold')
            ax.legend(fontsize=9)
        ax.set_title(title, fontweight='bold')
        ax.set_xlabel('Time (s)')
        ax.set_ylabel('PSI some avg10 (%)')
        ax.set_ylim(bottom=0)
    else:
        ax.text(0.5, 0.5, 'No data', ha='center', va='center',
                transform=ax.transAxes, color='gray')
        ax.set_title(title)

plt.tight_layout()
out = f"{PLOTS}/plot1_psi_comparison.png"
plt.savefig(out, dpi=150, bbox_inches='tight')
plt.close()
print(f"  Saved: {out}")

# ════════════════════════════════════════════════════════════
# PLOT 2 – Latency comparison: baseline vs under stress
# ════════════════════════════════════════════════════════════
print("[2/6] Latency comparison plot...")
fig, ax = plt.subplots(figsize=(12, 6))

experiments = [
    ('Baseline\n(no stress)',    'exp1_baseline/trial_2/wrk_baseline.txt',     '#4CAF50'),
    ('Baseline\n(under stress)', 'exp1_baseline/trial_2/wrk_under_stress.txt', '#8BC34A'),
    ('memory.max\n(baseline)',   'exp2_memory_max/trial_1/wrk_baseline.txt',   '#2196F3'),
    ('memory.max\n(after OOM)',  'exp2_memory_max/trial_1/wrk_after_oom.txt',  '#F44336'),
    ('high+max\n(baseline)',     'exp3_high_max/trial_1/wrk_baseline.txt',     '#FF9800'),
    ('swap_off\n(baseline)',     'exp5_swap/swap_off_trial_1/wrk_baseline.txt','#795548'),
    ('swap_off\n(after OOM)',    'exp5_swap/swap_off_trial_1/wrk_after.txt',   '#E91E63'),
]

labels, p50s, p90s, p99s, colors = [], [], [], [], []
for label, rel_path, color in experiments:
    w = load_wrk(f"{RESULTS}/{rel_path}")
    if w:
        labels.append(label)
        p50s.append(w.get('50%', 0))
        p90s.append(w.get('90%', 0))
        p99s.append(w.get('99%', 0))
        colors.append(color)

x = np.arange(len(labels))
w = 0.25
ax.bar(x - w,   p50s, w, label='p50', alpha=0.85, color=[c+'99' for c in colors[:len(labels)]])
ax.bar(x,       p90s, w, label='p90', alpha=0.85, color=colors)
ax.bar(x + w,   p99s, w, label='p99', alpha=0.85,
       color=colors, edgecolor='black', linewidth=0.5)

ax.set_xlabel('Experiment Configuration')
ax.set_ylabel('Latency (ms)')
ax.set_title('HTTP Latency: p50 / p90 / p99 Across Configurations', fontweight='bold')
ax.set_xticks(x)
ax.set_xticklabels(labels, fontsize=9)
ax.legend()
ax.set_yscale('log')
ax.yaxis.set_major_formatter(matplotlib.ticker.ScalarFormatter())

plt.tight_layout()
out = f"{PLOTS}/plot2_latency_comparison.png"
plt.savefig(out, dpi=150, bbox_inches='tight')
plt.close()
print(f"  Saved: {out}")

# ════════════════════════════════════════════════════════════
# PLOT 3 – memory.events: H1 proof (high vs max events)
# ════════════════════════════════════════════════════════════
print("[3/6] H1 proof plot (memory.events)...")
fig, ax = plt.subplots(figsize=(10, 5))

def read_events(path):
    out = {}
    try:
        with open(path) as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) == 2:
                    try: out[parts[0]] = int(parts[1])
                    except: pass
    except: pass
    return out

exp2_events = [read_events(f"{RESULTS}/exp2_memory_max/trial_{i}/memory_events_after.txt")
               for i in range(1,4)]
exp3_events = [read_events(f"{RESULTS}/exp3_high_max/trial_{i}/memory_events_after.txt")
               for i in range(1,4)]

trials = ['Trial 1', 'Trial 2', 'Trial 3']
x = np.arange(3)
w = 0.2

ax.bar(x - 1.5*w, [e.get('high',0)      for e in exp2_events], w,
       label='Exp2 high events',     color='#2196F3', alpha=0.8)
ax.bar(x - 0.5*w, [e.get('oom_kill',0)  for e in exp2_events], w,
       label='Exp2 oom_kill',        color='#F44336', alpha=0.8)
ax.bar(x + 0.5*w, [e.get('high',0)      for e in exp3_events], w,
       label='Exp3 high events',     color='#FF9800', alpha=0.8)
ax.bar(x + 1.5*w, [e.get('oom_kill',0)  for e in exp3_events], w,
       label='Exp3 oom_kill',        color='#9C27B0', alpha=0.8)

ax.set_xticks(x)
ax.set_xticklabels(trials)
ax.set_ylabel('Event count')
ax.set_title('H1: memory.max (OOM kills) vs memory.high (throttle events) — 3 Trials',
             fontweight='bold')
ax.legend()
plt.tight_layout()
out = f"{PLOTS}/plot3_h1_memory_events.png"
plt.savefig(out, dpi=150, bbox_inches='tight')
plt.close()
print(f"  Saved: {out}")

# ════════════════════════════════════════════════════════════
# PLOT 4 – H3: oom_score comparison
# ════════════════════════════════════════════════════════════
print("[4/6] H3 oom_score plot...")
fig, ax = plt.subplots(figsize=(8, 5))

server_scores, victim_scores = [], []
for i in range(1, 4):
    path = f"{RESULTS}/exp4_oom_adj/trial_{i}/oom_scores.csv"
    try:
        df = pd.read_csv(path)
        server_scores.append(int(df['server_oom_score'].iloc[0]))
        victim_scores.append(int(df['victim_oom_score'].iloc[0]))
    except:
        server_scores.append(0)
        victim_scores.append(0)

x = np.arange(3)
w = 0.3
bars1 = ax.bar(x - w/2, server_scores, w,
               label='HTTP server (adj=-500, protected)', color='#4CAF50', alpha=0.85)
bars2 = ax.bar(x + w/2, victim_scores, w,
               label='Victim process (adj=+500, target)', color='#F44336', alpha=0.85)

for bar in bars1:
    ax.text(bar.get_x()+bar.get_width()/2, bar.get_height()+10,
            str(int(bar.get_height())), ha='center', va='bottom', fontsize=9)
for bar in bars2:
    ax.text(bar.get_x()+bar.get_width()/2, bar.get_height()+10,
            str(int(bar.get_height())), ha='center', va='bottom', fontsize=9)

ax.set_xticks(x)
ax.set_xticklabels(['Trial 1','Trial 2','Trial 3'])
ax.set_ylabel('oom_score (higher = more likely to be killed)')
ax.set_title('H3: oom_score Comparison — Server (protected) vs Victim (targeted)',
             fontweight='bold')
ax.legend()
ax.set_ylim(0, max(victim_scores)*1.2 if victim_scores else 1200)
plt.tight_layout()
out = f"{PLOTS}/plot4_h3_oom_scores.png"
plt.savefig(out, dpi=150, bbox_inches='tight')
plt.close()
print(f"  Saved: {out}")

# ════════════════════════════════════════════════════════════
# PLOT 5 – H4: Swap on vs off — I/O PSI + time-to-OOM
# ════════════════════════════════════════════════════════════
print("[5/6] H4 swap comparison plot...")
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))
fig.suptitle('H4: Swap Enabled vs Disabled', fontweight='bold', fontsize=13)

# I/O PSI timeline comparison
for trial, color, label in [(1,'#F44336','swap_off t1'),(1,'#2196F3','swap_on t1')]:
    mode = 'swap_off' if 'off' in label else 'swap_on'
    path = f"{RESULTS}/exp5_swap/{mode}_trial_{trial}/psi.csv"
    df = load_psi(path)
    if df is not None and 'io_some_avg10' in df.columns:
        ax1.plot(df['time_s'], df['io_some_avg10'].astype(float),
                 color=color, linewidth=1.5, label=label)

ax1.set_xlabel('Time (s)')
ax1.set_ylabel('I/O PSI some avg10 (%)')
ax1.set_title('I/O PSI: swap_on vs swap_off')
ax1.legend()

# Time-to-OOM bar chart
tto_off = [6, 74, 6]
tto_on  = [120, 120, 120]  # ran to full timeout = no OOM
x = np.arange(3)
w = 0.3
ax2.bar(x - w/2, tto_off, w, label='swap_off (OOM triggered)', color='#F44336', alpha=0.85)
ax2.bar(x + w/2, tto_on,  w, label='swap_on (no OOM, full run)', color='#4CAF50', alpha=0.85)
ax2.set_xticks(x)
ax2.set_xticklabels(['Trial 1','Trial 2','Trial 3'])
ax2.set_ylabel('Time (seconds)')
ax2.set_title('Time-to-OOM: swap_off vs swap_on')
ax2.legend()
ax2.axhline(y=120, color='gray', linestyle=':', linewidth=1, label='max duration')

plt.tight_layout()
out = f"{PLOTS}/plot5_h4_swap_comparison.png"
plt.savefig(out, dpi=150, bbox_inches='tight')
plt.close()
print(f"  Saved: {out}")

# ════════════════════════════════════════════════════════════
# PLOT 6 – H2: PSI warning timeline
# ════════════════════════════════════════════════════════════
print("[6/6] H2 PSI warning plot...")
fig, axes = plt.subplots(1, 3, figsize=(15, 5))
fig.suptitle('H2: PSI Early Warning — avg10 vs 15% Threshold (3 Trials)',
             fontweight='bold', fontsize=13)

for i, ax in enumerate(axes, 1):
    path = f"{RESULTS}/exp6_psi_warning/trial_{i}/psi_warning_log.csv"
    try:
        df = pd.read_csv(path)
        df.columns = df.columns.str.strip()
        df['time_s'] = range(len(df))
        psi_col = [c for c in df.columns if 'psi' in c.lower() and 'avg10' in c.lower()]
        if not psi_col:
            psi_col = [df.columns[1]]
        psi_vals = df[psi_col[0]].astype(float)
        ax.plot(df['time_s'], psi_vals, color='#2196F3', linewidth=1.5, label='PSI avg10')
        ax.fill_between(df['time_s'], psi_vals, alpha=0.15, color='#2196F3')
        ax.axhline(y=15, color='red', linestyle='--', linewidth=1.5, label='15% threshold')
        # mark warning point
        warn_idx = df[df[psi_col[0]].astype(float) > 15].index
        if len(warn_idx) >= 10:
            wp = warn_idx[9]
            ax.axvline(x=df['time_s'].iloc[wp], color='orange',
                       linestyle=':', linewidth=2, label='Warning issued')
        ax.set_title(f'Trial {i}', fontweight='bold')
        ax.set_xlabel('Time (s)')
        ax.set_ylabel('PSI some avg10 (%)')
        ax.legend(fontsize=9)
        ax.set_ylim(bottom=0)
    except Exception as e:
        ax.text(0.5, 0.5, f'No data\n{e}', ha='center', va='center',
                transform=ax.transAxes, color='gray', fontsize=9)
        ax.set_title(f'Trial {i}')

plt.tight_layout()
out = f"{PLOTS}/plot6_h2_psi_warning.png"
plt.savefig(out, dpi=150, bbox_inches='tight')
plt.close()
print(f"  Saved: {out}")

# ════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════
print("\n" + "=" * 60)
print("  ALL PLOTS GENERATED SUCCESSFULLY")
print("=" * 60)
plots = glob.glob(f"{PLOTS}/*.png")
for p in sorted(plots):
    size = os.path.getsize(p) // 1024
    print(f"  {os.path.basename(p):45s} {size:4d} KB")
print(f"\n  Total: {len(plots)} plots saved to {PLOTS}/")
