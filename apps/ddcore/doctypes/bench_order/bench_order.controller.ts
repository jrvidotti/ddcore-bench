import { defineController } from "@ddcore/sdk";
import type { BenchOrder } from "../../.ddcore/types";

// Mirrors apps/frappe/.../bench_order.py: same rule, same rounding.
export default defineController<BenchOrder>("Bench Order", {
  validate(doc) {
    let total = 0;
    for (const row of doc.items || []) {
      row.amount = Math.round(row.qty * row.rate * 100) / 100;
      total += row.amount;
    }
    doc.total = Math.round(total * 100) / 100;
  },
});
