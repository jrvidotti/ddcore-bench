# Phase 1 — ddcore × Frappe

```
host: Darwin 25.6.0 arm64, 10 cpus
docker: 29.8.0
ddcore: 0.21.10
frappe: __version__ = "16.35.0"
limits: app cpus=2 mem=2g; db cpus=2 mem=2g
```

## Resources

| Metric | ddcore | Frappe |
|---|---:|---:|
| App image size | 77 MB | 4100 MB |
| First boot (DB init + schema, until ready) | 4 s | 19 s |
| Warm restart of the app until ready | 0.44 s | 0.85 s |
| Idle memory, whole stack | 155 MiB (2 containers) | 598 MiB (7 containers) |

## Latency — 1 connection, sequential

| Endpoint | ddcore p50 / p95 | Frappe p50 / p95 | p50 |
|---|---:|---:|---:|
| ping | 0.3 / 0.3 ms | 4.3 / 4.9 ms | 15.0× ddcore |
| get_order | 0.5 / 0.5 ms | 2.5 / 2.9 ms | 5.2× ddcore |
| list_orders | 0.5 / 0.7 ms | 2.7 / 3.2 ms | 5.2× ddcore |
| summary | 0.6 / 0.7 ms | 2.4 / 2.8 ms | 4.1× ddcore |
| insert_order | 1.4 / 1.9 ms | 4.3 / 5.1 ms | 3.1× ddcore |

## Throughput — 10 connections

| Endpoint | ddcore req/s (p95) | Frappe req/s (p95) | req/s | errors d/f | peak stack mem d/f |
|---|---:|---:|---:|---:|---:|
| ping | 13821 (1.1 ms) | 464 (88.7 ms) | 29.8× ddcore | 0.0%/0.0% | 279/944 MiB |
| get_order | 7442 (1.9 ms) | 447 (88.3 ms) | 16.7× ddcore | 0.0%/0.0% | 428/964 MiB |
| list_orders | 5815 (2.7 ms) | 437 (87.0 ms) | 13.3× ddcore | 0.0%/0.0% | 409/972 MiB |
| summary | 5220 (2.7 ms) | 482 (85.1 ms) | 10.8× ddcore | 0.0%/0.0% | 533/975 MiB |
| insert_order | 750 (29.0 ms) | 286 (83.5 ms) | 2.6× ddcore | 0.0%/0.0% | 400/1081 MiB |

## Throughput — 50 connections

| Endpoint | ddcore req/s (p95) | Frappe req/s (p95) | req/s | errors d/f | peak stack mem d/f |
|---|---:|---:|---:|---:|---:|
| ping | 13775 (4.9 ms) | 608 (161.2 ms) | 22.6× ddcore | 0.0%/0.0% | 411/959 MiB |
| get_order | 6518 (10.2 ms) | 569 (181.4 ms) | 11.5× ddcore | 0.0%/0.0% | 445/968 MiB |
| list_orders | 5157 (13.6 ms) | 522 (184.3 ms) | 9.9× ddcore | 0.0%/0.0% | 499/976 MiB |
| summary | 4951 (12.5 ms) | 564 (191.4 ms) | 8.8× ddcore | 0.0%/0.0% | 492/976 MiB |
| insert_order | 740 (84.1 ms) | 256 (296.9 ms) | 2.9× ddcore | 0.0%/0.0% | 570/1155 MiB |
