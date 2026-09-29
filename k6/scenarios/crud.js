// One operation at a time, to isolate it: -e OP=get|list|insert|submit|update|summary|ping
import { T, send, loadIds, pick, STATUSES, newOrder, profile, perOp } from "../lib/common.js";

export const options = {
  scenarios: { op: profile() },
  thresholds: { checks: ["rate>0.99"], ...perOp },
  summaryTrendStats: ["avg", "p(50)", "p(95)", "p(99)", "max"],
};

export const setup = loadIds;
const OP = __ENV.OP || "get";

export default function (data) {
  const o = pick(data.orders);
  switch (OP) {
    case "get": return send("get", T.get("Bench Order", o.id));
    case "list": return send("list", T.list("Bench Order", {
      fields: ["id", "customer", "status", "total", "order_date"],
      filters: { status: pick(STATUSES) }, orderBy: "order_date desc", limit: 20 }));
    case "insert": return send("insert", T.insert("Bench Order", newOrder(o.customer)));
    case "submit": {
      const res = send("insert", T.insert("Bench Order", newOrder(o.customer)));
      return send("submit", T.submit(T.idOf(JSON.parse(res.body).data)));
    }
    case "update": return send("update", T.update("Bench Customer", o.customer, { city: pick(["Lisbon", "Porto"]) }));
    case "summary": return send("summary", T.summary(o.customer));
    case "ping": return send("ping", T.ping());
  }
}
