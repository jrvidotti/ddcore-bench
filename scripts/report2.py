#!/usr/bin/env python3
"""k6 report: every run of run-all.sh, ddcore next to Frappe."""
import json, re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from report import stack_mem, mem_mib  # noqa: E402  (report.py prints on import; see below)

out = Path(sys.argv[1] if len(sys.argv) > 1 else "results/latest")
runs = {}
for f in sorted(((out / "k6") if (out / "k6").is_dir() else out).glob("*.json")):
    m = re.match(r"(.+)-(ddcore|frappe)-\d{6}$", f.stem)
    if not m:
        continue
    d = json.loads(f.read_text())["metrics"]
    cpu = []
    stats = f.with_suffix(".stats.csv")
    if stats.exists():
        # sum of the stack's CPU per sample
        sample, cur = [], {}
        for line in stats.read_text(errors="ignore").splitlines():
            parts = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", line).split(",")
            if len(parts) != 3 or not parts[2].strip().endswith("%"):
                continue
            n = parts[0].strip()
            if n in cur:
                sample.append(sum(cur.values())); cur = {}
            cur[n] = float(parts[2].strip().rstrip("%"))
        if cur:
            sample.append(sum(cur.values()))
        cpu = sample
    mem = stack_mem(stats) if stats.exists() else None
    runs.setdefault(m.group(1), {})[m.group(2)] = {
        "d": d, "cpu_peak": max(cpu) if cpu else None,
        "cpu_avg": sum(cpu) / len(cpu) if cpu else None, "mem": mem[0] if mem else None,
    }


def g(d, metric, k):
    v = d.get(metric, {}).get(k)
    return v


def cell(r):
    if not r:
        return "–"
    d = r["d"]
    rps = g(d, "http_reqs", "rate") or 0
    fail = (g(d, "http_req_failed", "value") or 0) * 100
    dur = "http_req_duration{expected_response:true}" if "http_req_duration{expected_response:true}" in d else "http_req_duration"
    p50, p95, p99 = (g(d, dur, k) for k in ("p(50)", "p(95)", "p(99)"))
    f = lambda v: f"{v:.1f}" if v is not None else "n/a"
    res = f"{rps:.0f} req/s · p50 {f(p50)} · p95 {f(p95)} · p99 {f(p99)} ms"
    if fail:
        res += f" · **{fail:.1f}% err**"
    if r["mem"]:
        res += f" · {r['mem']:.0f} MiB"
    if r["cpu_avg"] is not None:
        res += f" · CPU {r['cpu_avg']:.0f}% avg"
    return res


ORDER = ["smoke", "ramp", "ramp-cpu1", "ramp-cpu4", "rate100", "crud-ping", "crud-get", "crud-list",
         "crud-summary", "crud-insert", "crud-submit", "crud-update", "soak"]
names = sorted(runs, key=lambda n: ORDER.index(n) if n in ORDER else 99)
print("# Phase 2 (k6) — ddcore × Frappe\n")
print("Latency counts successful responses only; stack memory is the peak of the sampled sum, "
      "CPU the average sum across containers (100% = one core).\n")
print("| Run | ddcore | Frappe |\n|---|---|---|")
for n in names:
    print(f"| {n} | {cell(runs[n].get('ddcore'))} | {cell(runs[n].get('frappe'))} |")

print("\n## Per operation inside the mixed runs (p95 ms)\n")
ops = ["get", "list", "insert", "submit", "update", "summary", "ping"]
print("| Run | Target | " + " | ".join(ops) + " |\n|---|---|" + "---:|" * len(ops))
for n in names:
    if not (n.startswith("ramp") or n in ("rate100", "soak")):
        continue
    for t in ("ddcore", "frappe"):
        r = runs[n].get(t)
        if not r:
            continue
        vals = [g(r["d"], f"http_req_duration{{op:{op}}}", "p(95)") for op in ops]
        print(f"| {n} | {t} | " + " | ".join(f"{v:.1f}" if v else "–" for v in vals) + " |")
