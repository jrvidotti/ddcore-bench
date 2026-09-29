# ddcore-bench

Performance comparison between [ddcore](https://github.com/jrvidotti/ddcore) and
[Frappe](https://frappe.io), running **the same app** (`benchapp`) on both.

|        | ddcore                                                   | Frappe                                                               |
| ------ | -------------------------------------------------------- | -------------------------------------------------------------------- |
| Image  | `ghcr.io/jrvidotti/ddcore:<DDCORE_VERSION>` + app        | `frappe/erpnext:v16.x` + app (ERPNext not installed on the site)     |
| Stack  | 1 process (HTTP + job workers + scheduler) + Postgres 17 | gunicorn + RQ worker + scheduler + socketio + 2 Redis + MariaDB 11.8 |
| Port   | 8101                                                     | 8102 (gunicorn directly, no nginx)                                   |
| Limits | app 2 CPU / 2 GB, DB 2 CPU / 2 GB                        | same                                                                 |

## The app

`Bench Customer`, `Bench Order` (submittable, child table `Bench Order Item`, `total`
computed in `validate`), and two whitelisted methods: `ping` (no DB) and `summary(customer)`
(one SQL aggregate). `apps/ddcore` and `apps/frappe/benchapp` implement the same rules;
`k6/lib/adapter.js` is the one place where the two HTTP APIs differ.

## Running

```bash
brew install k6 oha           # load generators
make setup-ddcore           # fresh stack, boot time, API key → .env.bench
scripts/setup.sh frappe
set -a; . ./.env.bench; set +a
npm run seed -- ddcore        # 1 000 customers, 10 000 orders × 5 items (deterministic)
npm run seed -- frappe        # --customers N --orders N --concurrency N

# Phase 1: simple metrics (image, boot, idle memory, latency, throughput) → REPORT.md
scripts/run-phase1.sh

# Phase 2: k6 (start only the stack under test)
scripts/k6.sh ddcore k6/scenarios/mix.js                          # smoke: 1 VU × 10, checks must be 100%
scripts/k6.sh ddcore k6/scenarios/mix.js  -e PROFILE=ramp         # find the knee
scripts/k6.sh frappe k6/scenarios/mix.js  -e PROFILE=rate -e RATE=100
scripts/k6.sh ddcore k6/scenarios/crud.js -e OP=insert -e PROFILE=rate -e RATE=50
```

Knobs: `APP_CPUS`, `APP_MEM`, `DB_CPUS`, `DB_MEM`, `DDCORE_VERSION`, `PG_POOL`,
`GUNICORN_WORKERS` (default 5 = 2×CPU+1), `GUNICORN_THREADS`; ddcore's `workers` is in
`compose/ddcore.json` (the goja pool is `workers + 4`).

## Fairness rules

- One stack running at a time; the load generator runs on the host.
- Same data (seeded through each API with the same PRNG seed), same indexes.
- Warm-up discarded; repeat each run and report the median; record versions (`versions.txt`).
- A run whose checks are below 99 % is not a result.
