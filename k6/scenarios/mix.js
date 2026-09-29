// Realistic mix: 70% reads, 20% writes, 10% methods.
//   scripts/k6.sh <ddcore|frappe> k6/scenarios/mix.js -e PROFILE=ramp
import { T, send, loadIds, pick, STATUSES, newOrder, profile, perOp } from "../lib/common.js";

export const options = {
  scenarios: { mix: profile() },
  thresholds: { checks: ["rate>0.99"], ...perOp },
  summaryTrendStats: ["avg", "p(50)", "p(95)", "p(99)", "max"],
};

export const setup = loadIds;

export default function (data) {
  const o = pick(data.orders);
  const r = Math.random();
  if (r < 0.40) send("get", T.get("Bench Order", o.id));
  else if (r < 0.70) send("list", T.list("Bench Order", {
    fields: ["id", "customer", "status", "total", "order_date"],
    filters: { status: pick(STATUSES) }, orderBy: "order_date desc", limit: 20 }));
  else if (r < 0.80) send("insert", T.insert("Bench Order", newOrder(o.customer)));
  else if (r < 0.85) {
    const res = send("insert", T.insert("Bench Order", newOrder(o.customer)));
    if (res.status < 300) send("submit", T.submit(T.idOf(JSON.parse(res.body).data)));
  } else if (r < 0.90) send("update", T.update("Bench Customer", o.customer, { credit_limit: Math.round(Math.random() * 1e5) / 100 }));
  else if (r < 0.95) send("summary", T.summary(o.customer));
  else send("ping", T.ping());
}
