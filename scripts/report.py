#!/usr/bin/env python3
"""Phase 1 report: one Markdown table per metric group, ddcore next to Frappe."""
import csv, json, re, sys
from pathlib import Path

out = Path(sys.argv[1] if len(sys.argv) > 1 else "results/latest")
T = ["ddcore", "frappe"]


def mem_mib(s):
    v, unit = re.match(r"([\d.]+)\s*([KMG]i?B)", s.split("/")[0].strip()).groups()
    return float(v) * {"KiB": 1 / 1024, "MiB": 1, "GiB": 1024, "kB": 1 / 1024, "MB": 1, "GB": 1024}[unit]


def stack_mem(path):
    """Sum of every container's memory; for a sampled run, the peak of the per-sample sums."""
    if not path.exists():
        return None
    rows = [r for r in csv.reader(open(path, errors="ignore")) if len(r) == 3 and "/" in r[1]]
    names = {re.sub(r"^\W+", "", r[0]) for r in rows}
    if not rows:
        return None
    per_sample, cur = [], {}
    for r in rows:
        n = re.sub(r"^\W+", "", r[0])
        if n in cur:
            per_sample.append(sum(cur.values())); cur = {}
        cur[n] = mem_mib(r[1])
    per_sample.append(sum(cur.values()))
    return max(per_sample), len(names)


def ms(x, k):
    v = x["latencyPercentiles"][k]
    return v * 1000 if v is not None else None


def fmt(v, unit=" ms"):
    return f"{v:.1f}{unit}" if v is not None else "n/a"


def ratio(a, b, higher_better):
    if not a or not b:
        return ""
    r = a / b if higher_better else b / a
    return f"{r:.1f}× {'ddcore' if r >= 1 else 'frappe'}" if abs(r - 1) > 0.05 else "≈"


def main():
    print(f"# Phase 1 — ddcore × Frappe\n\n```\n{(out / 'versions.txt').read_text().strip()}\n```\n")

    print("## Resources\n\n| Metric | ddcore | Frappe |\n|---|---:|---:|")
    img = {t: int((out / t / "image_bytes").read_text()) / 1e6 for t in T if (out / t / "image_bytes").exists()}
    print(f"| App image size | {img.get('ddcore', 0):.0f} MB | {img.get('frappe', 0):.0f} MB |")
    boot = {t: json.loads((out / f"boot-{t}.json").read_text()) for t in T if (out / f"boot-{t}.json").exists()}
    if boot:
        print(f"| First boot (DB init + schema, until ready) | {boot['ddcore']['first_boot_s']} s | {boot['frappe']['first_boot_s']} s |")
        print(f"| Warm restart of the app until ready | {boot['ddcore']['warm_boot_s']} s | {boot['frappe']['warm_boot_s']} s |")
    idle = {t: stack_mem(out / t / "idle_stats.csv") for t in T}
    if all(idle.values()):
        print(f"| Idle memory, whole stack | {idle['ddcore'][0]:.0f} MiB ({idle['ddcore'][1]} containers) | "
              f"{idle['frappe'][0]:.0f} MiB ({idle['frappe'][1]} containers) |")

    print("\n## Latency — 1 connection, sequential\n\n| Endpoint | ddcore p50 / p95 | Frappe p50 / p95 | p50 |\n|---|---:|---:|---:|")
    eps = [l.split("\t")[0] for l in (out / "ddcore" / "endpoints.tsv").read_text().splitlines()]


    def load(t, ep, c):
        p = out / t / f"{ep}.c{c}.json"
        return json.loads(p.read_text()) if p.exists() else None


    for ep in eps:
        d = {t: load(t, ep, 1) for t in T}
        if not all(d.values()):
            continue
        f = lambda x: f"{fmt(ms(x, 'p50'), '')} / {fmt(ms(x, 'p95'))}"
        print(f"| {ep} | {f(d['ddcore'])} | {f(d['frappe'])} | {ratio(ms(d['ddcore'], 'p50'), ms(d['frappe'], 'p50'), False)} |")

    for c in (10, 50):
        print(f"\n## Throughput — {c} connections\n\n| Endpoint | ddcore req/s (p95) | Frappe req/s (p95) | req/s | errors d/f | peak stack mem d/f |\n|---|---:|---:|---:|---:|---:|")
        for ep in eps:
            d = {t: load(t, ep, c) for t in T}
            if not all(d.values()):
                continue
            # oha counts failed connections as requests: req/s here is successful requests only
            rps = {t: d[t]["summary"]["requestsPerSec"] * (d[t]["summary"]["successRate"] or 0) for t in T}
            err = "/".join(f"{(1 - (d[t]['summary']['successRate'] or 0)) * 100:.1f}%" for t in T)
            mem = {t: stack_mem(out / t / f"{ep}.c{c}.stats.csv") for t in T}
            mems = "/".join(f"{mem[t][0]:.0f}" if mem[t] else "–" for t in T) + " MiB"
            print(f"| {ep} | {rps['ddcore']:.0f} ({fmt(ms(d['ddcore'], 'p95'))}) | "
                  f"{rps['frappe']:.0f} ({fmt(ms(d['frappe'], 'p95'))}) | "
                  f"{ratio(rps['ddcore'], rps['frappe'], True)} | {err} | {mems} |")


if __name__ == "__main__":
    main()
