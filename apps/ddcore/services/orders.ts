import { whitelisted } from "@ddcore/sdk";

// No database access: measures the framework and runtime overhead alone.
export const ping = whitelisted(() => "pong");

// One aggregate over a customer's orders; mirrors benchapp.api.summary.
export const summary = whitelisted((args: { customer: string }) => {
  const rows = ddcore.db.sql(
    "SELECT count(*) AS orders, coalesce(sum(total), 0) AS total FROM tab_bench_order WHERE customer = $1",
    [args.customer],
  );
  return { orders: Number(rows[0].orders), total: Number(rows[0].total) };
});
