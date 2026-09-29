// Shared k6 plumbing: which target, the request helper, the ids a run needs.
import http from "k6/http";
import { check } from "k6";
import { target } from "./adapter.js";

export const T = target(__ENV.TARGET || "ddcore", { token: __ENV.TOKEN, base: __ENV.BASE });

// Every request is tagged with its operation, so k6 reports p95 per op.
export function send(op, r) {
  const res = http.request(r.method, r.url, r.body ?? null, { headers: T.headers, tags: { op } });
  check(res, { [`${op} 2xx`]: (x) => x.status >= 200 && x.status < 300 });
  return res;
}

// A pool of existing ids, read once per run in setup().
export function loadIds() {
  const rows = (r) => JSON.parse(http.request(r.method, r.url, null, { headers: T.headers }).body).data;
  const orders = rows(T.list("Bench Order", { fields: ["id", "customer"], orderBy: "order_date desc", limit: 2000 }));
  if (!orders || orders.length === 0) throw new Error("no orders: seed the target first");
  return { orders: orders.map((o) => ({ id: T.idOf(o), customer: o.customer })) };
}

export const pick = (a) => a[Math.floor(Math.random() * a.length)];
export const STATUSES = ["Open", "Paid", "Shipped"];

export function newOrder(customer) {
  return {
    customer,
    order_date: "2025-06-01",
    items: [1, 2, 3, 4, 5].map((i) => ({ item: `SKU-${i}`, qty: i, rate: 10.5 })),
  };
}

// Load profiles, chosen with -e PROFILE=… (smoke is the default).
export function profile() {
  switch (__ENV.PROFILE || "smoke") {
    case "smoke":
      return { executor: "per-vu-iterations", vus: 1, iterations: 10 };
    case "ramp": // find the knee: VUs grow until latency or errors break
      return { executor: "ramping-vus", startVUs: 1, stages: [
        { duration: "1m", target: 20 }, { duration: "1m", target: 50 },
        { duration: "1m", target: 100 }, { duration: "1m", target: 200 }, { duration: "30s", target: 0 } ] };
    case "rate": // same arrival rate on both targets: compare latency at equal load
      return { executor: "constant-arrival-rate", rate: Number(__ENV.RATE || 100), timeUnit: "1s",
        duration: __ENV.DURATION || "2m", preAllocatedVUs: 50, maxVUs: 500 };
    case "soak": // memory leaks, pool exhaustion
      return { executor: "constant-arrival-rate", rate: Number(__ENV.RATE || 50), timeUnit: "1s",
        duration: __ENV.DURATION || "30m", preAllocatedVUs: 50, maxVUs: 300 };
    default:
      throw new Error(`unknown PROFILE ${__ENV.PROFILE}`);
  }
}

// A (loose) threshold per op makes k6 print and export that op's latency on its own.
// The expected_response one is latency of successful responses only.
export const perOp = Object.fromEntries(
  ["get", "list", "insert", "submit", "update", "summary", "ping"]
    .map((op) => [`http_req_duration{op:${op}}`, ["p(95)<10000"]])
    .concat([["http_req_duration{expected_response:true}", ["p(95)<10000"]]]),
);
