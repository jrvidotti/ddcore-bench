# ddcore 0.21.10 × Frappe 16.35 — full run 2026-09-28 23:07 → 01:07

Same app on both (customers, submittable orders with a 5-row child table, total computed
in `validate`, two whitelisted methods), same seed (1 000 customers, 10 000 orders), app
and DB limited to 2 CPU / 2 GB each unless noted. Host: M-series Mac, Docker Desktop.
Details: `phase1/REPORT.md` (oha) and `REPORT-k6.md` (k6).

## Headline

| | ddcore | Frappe | |
|---|---:|---:|---|
| App image | 77 MB | 4.1 GB | ERPNext ships in the official image |
| First boot → ready | 4 s | 19 s | |
| Idle memory, whole stack | 155 MiB (2 containers) | 598 MiB (7 containers) | |
| Latency, 1 connection, p50 | 0.3–1.4 ms | 2.4–4.3 ms | ddcore 3–15× lower |
| Reads, 10 connections | 5 200–13 800 req/s | 440–480 req/s | ddcore 11–30× |
| Inserts (5 rows), 10–50 connections | 740–750 req/s, 0% err | 256–286 req/s | ddcore ~2.8× |
| Mixed ramp to 200 VUs (2 CPU) | 2 055 req/s, p95 97 ms, 0% err | 475 req/s, p95 485 ms, 11% err | ddcore 4.3× |
| Seed via API (10k orders, 16 conns) | 12 s | 42 s | |
| Soak 30 min at 50 req/s, p95 | 6.2 ms, app 97–240 MiB, no growth | 7.5 ms | both stable |

At low, fixed rates (50–200 req/s, `crud-*`, `rate100`) both answer in 2–7 ms p95 and the
difference is small — Frappe is not slow per request when it is not saturated. The gap
is capacity: how much load each absorbs before latency and errors climb.

## Findings

1. **ddcore < 0.21.10: API key auth ran Argon2 (64 MiB) per request** — 31 req/s ceiling,
   OOM at 50 connections. Fixed in 0.21.10 (issue #29): ping went 32 → 3 248 req/s at c=1,
   14 456 at c=50; seed 393 s → 12 s. Results of the broken run are kept in
   `results/2026-09-28-ddcore-0.21.9-argon2-oom`.
2. **Frappe fails concurrent inserts instead of queueing them.** MariaDB 11.8's snapshot
   isolation turns contention on the naming-series row (`tabSeries`) into error 1020, which
   Frappe returns as `500 QueryDeadlockError` for the client to retry: 90% of inserts at
   100 connections, 32% under 700 req/s mixed overload, 57% of inserts in the 2-CPU ramp.
   The seed needed 3 012 retries for 10 000 orders. `MARIADB_SNAPSHOT_ISOLATION=OFF` is the
   variant to measure next.
3. **ddcore's mixed throughput does not scale with CPU**: 2 421 / 2 055 / 2 163 req/s at
   1 / 2 / 4 app CPUs; at 4 CPUs the app averages 186% and Postgres 132%, neither saturated.
   Inserts are flat at ~745 req/s from 10 to 50 connections too. Likely a serialisation
   point on the write path (the naming-series row lock held to commit, or the pools:
   `pool_max_conns=20`, goja runtimes = workers + 4 = 8). Not yet isolated.
4. **Frappe scales with CPU**: 226 / 475 / 737 req/s at 1 / 2 / 4 CPUs (gunicorn 2×CPU+1
   workers), with its error rate rising alongside (7 / 11 / 19%).
5. Frappe read errors in the closed-loop ramps (3–12% of get/list) did not reproduce under
   open-loop overload or with 200 concurrent GETs, and left no application exception —
   probably connection-level at 200 VUs. Not isolated.

## Caveats

- One run of each scenario; the plan's "3 runs, median" is still to do.
- Load generator on the same host as both stacks (Docker Desktop VM); absolute numbers are
  host-specific, the ratios are the result.
- Frappe hit through gunicorn directly (no nginx), ddcore through its own process.
