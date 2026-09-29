# Phase 2 (k6) — ddcore × Frappe

Latency counts successful responses only; stack memory is the peak of the sampled sum, CPU the average sum across containers (100% = one core).

| Run | ddcore | Frappe |
|---|---|---|
| smoke | 127 req/s · p50 0.6 · p95 34.6 · p99 57.9 ms | 148 req/s · p50 2.9 · p95 20.4 · p99 25.0 ms |
| ramp | 2055 req/s · p50 25.0 · p95 97.0 · p99 146.9 ms · **0.0% err** · 476 MiB · CPU 265% avg | 475 req/s · p50 95.1 · p95 485.1 · p99 715.6 ms · **11.1% err** · 866 MiB · CPU 247% avg |
| ramp-cpu1 | 2421 req/s · p50 13.2 · p95 98.4 · p99 130.2 ms · **0.0% err** · 616 MiB · CPU 190% avg | 226 req/s · p50 205.8 · p95 882.2 · p99 1106.9 ms · **7.4% err** · 922 MiB · CPU 127% avg |
| ramp-cpu4 | 2163 req/s · p50 24.2 · p95 91.5 · p99 122.2 ms · **0.0% err** · 780 MiB · CPU 318% avg | 737 req/s · p50 47.0 · p95 357.6 · p99 886.8 ms · **19.3% err** · 1258 MiB · CPU 462% avg |
| rate100 | 105 req/s · p50 2.4 · p95 6.4 · p99 8.8 ms · 508 MiB · CPU 26% avg | 105 req/s · p50 2.8 · p95 5.3 · p99 6.3 ms · 1194 MiB · CPU 35% avg |
| crud-ping | 200 req/s · p50 1.3 · p95 1.6 · p99 1.9 ms · 512 MiB · CPU 19% avg | 200 req/s · p50 1.9 · p95 2.2 · p99 2.8 ms · 1195 MiB · CPU 42% avg |
| crud-get | 200 req/s · p50 2.2 · p95 2.6 · p99 2.9 ms · 511 MiB · CPU 34% avg | 200 req/s · p50 2.1 · p95 2.5 · p99 3.0 ms · 1208 MiB · CPU 45% avg |
| crud-list | 200 req/s · p50 2.1 · p95 2.6 · p99 2.9 ms · 521 MiB · CPU 34% avg | 200 req/s · p50 2.3 · p95 2.5 · p99 3.3 ms · 1220 MiB · CPU 47% avg |
| crud-summary | 200 req/s · p50 2.2 · p95 3.1 · p99 3.6 ms · 514 MiB · CPU 39% avg | 200 req/s · p50 2.0 · p95 2.5 · p99 3.3 ms · 1225 MiB · CPU 44% avg |
| crud-insert | 50 req/s · p50 5.8 · p95 6.9 · p99 7.6 ms · 519 MiB · CPU 26% avg | 50 req/s · p50 5.4 · p95 6.4 · p99 7.7 ms · 1229 MiB · CPU 27% avg |
| crud-submit | 100 req/s · p50 2.6 · p95 3.2 · p99 5.4 ms · 520 MiB · CPU 24% avg | 100 req/s · p50 4.1 · p95 4.5 · p99 5.5 ms · 1231 MiB · CPU 38% avg |
| crud-update | 50 req/s · p50 3.6 · p95 4.4 · p99 5.0 ms · 524 MiB · CPU 15% avg | 50 req/s · p50 4.7 · p95 5.7 · p99 7.1 ms · 1236 MiB · CPU 26% avg |
| soak | 53 req/s · p50 2.4 · p95 6.2 · p99 7.6 ms · 825 MiB · CPU 15% avg | 53 req/s · p50 4.0 · p95 7.5 · p99 8.9 ms · 1210 MiB · CPU 26% avg |

## Per operation inside the mixed runs (p95 ms)

| Run | Target | get | list | insert | submit | update | summary | ping |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| ramp | ddcore | 81.5 | 81.7 | 133.6 | 101.7 | 98.3 | 98.3 | 97.0 |
| ramp | frappe | 482.8 | 485.6 | 498.0 | 489.0 | 488.6 | 479.0 | 483.8 |
| ramp-cpu1 | ddcore | 88.5 | 88.3 | 132.3 | 104.8 | 102.6 | 102.2 | 101.6 |
| ramp-cpu1 | frappe | 880.4 | 878.9 | 898.8 | 904.7 | 886.8 | 871.7 | 821.0 |
| ramp-cpu4 | ddcore | 78.5 | 78.6 | 125.3 | 98.1 | 94.3 | 94.9 | 93.0 |
| ramp-cpu4 | frappe | 332.9 | 330.9 | 353.8 | 324.4 | 381.8 | 323.0 | 329.2 |
| rate100 | ddcore | 2.9 | 3.1 | 9.0 | 5.2 | 4.3 | 4.1 | 1.8 |
| rate100 | frappe | 3.1 | 3.5 | 5.8 | 7.1 | 4.2 | 2.9 | 2.7 |
| soak | ddcore | 2.7 | 2.8 | 7.7 | 4.8 | 4.2 | 5.7 | 1.7 |
| soak | frappe | 5.3 | 5.8 | 9.0 | 8.5 | 7.1 | 5.2 | 4.7 |
