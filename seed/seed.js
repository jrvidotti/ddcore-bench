// Deterministic seed: the same SEED produces the same customers and orders on
// both targets, through the public API (so it exercises the same code paths).
//   node seed/seed.js <ddcore|frappe> [--customers 1000] [--orders 10000] [--concurrency 16]
import { target } from "../k6/lib/adapter.js";

const args = process.argv.slice(2);
const name = args[0];
const opt = (k, d) => {
  const i = args.indexOf(`--${k}`);
  return i >= 0 ? Number(args[i + 1]) : d;
};
const N_CUSTOMERS = opt("customers", 1000);
const N_ORDERS = opt("orders", 10000);
const CONCURRENCY = opt("concurrency", 16);
const token = process.env[`TOKEN_${(name || "").toUpperCase()}`];
if (!token) throw new Error(`set TOKEN_${(name || "").toUpperCase()} (see scripts/setup.sh)`);
const t = target(name, { token });

// mulberry32: small, fast, reproducible
function rng(seed) {
  return () => {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let x = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    x = (x + Math.imul(x ^ (x >>> 7), 61 | x)) ^ x;
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(42);
const pick = (a) => a[Math.floor(rand() * a.length)];
const CITIES = ["Lisbon", "Porto", "São Paulo", "Recife", "Curitiba", "Madrid", "Berlin", "Austin", "Lagos", "Osaka"];
const STATUSES = ["Open", "Paid", "Shipped"];

// Network errors (reset, refused) are retried with backoff; an HTTP error is not,
// since a 4xx/5xx means the request reached the app and a retry could duplicate it.
let retries = 0;
async function send(req, attempt = 1) {
  let r;
  try {
    r = await fetch(req.url, { method: req.method, headers: t.headers, body: req.body ?? undefined });
  } catch (e) {
    if (attempt >= 5) throw e;
    await new Promise((ok) => setTimeout(ok, 500 * 2 ** attempt));
    return send(req, attempt + 1);
  }
  const text = await r.text();
  // Frappe reports a write conflict (a deadlock, or MariaDB's snapshot-isolation
  // error 1020 on tabSeries under concurrent inserts) as a 500 QueryDeadlockError
  // after rolling the transaction back — the client is expected to retry.
  if (r.status >= 500 && text.includes("QueryDeadlockError") && attempt < 20) {
    retries++;
    // exponential backoff with jitter, capped at 2s: 16 writers contend for one row
    const wait = Math.min(2000, 20 * 2 ** attempt) * (0.5 + Math.random());
    await new Promise((ok) => setTimeout(ok, wait));
    return send(req, attempt + 1);
  }
  if (!r.ok) throw new Error(`${req.method} ${req.url} → ${r.status}: ${text.slice(0, 300)}`);
  return JSON.parse(text);
}

async function pool(items, fn) {
  const out = new Array(items.length);
  let next = 0, done = 0;
  const started = Date.now();
  await Promise.all(Array.from({ length: CONCURRENCY }, async () => {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i]);
      if (++done % 1000 === 0) process.stdout.write(`  ${done}/${items.length} (${Math.round(done / ((Date.now() - started) / 1000))}/s)\n`);
    }
  }));
  return out;
}

// Generate everything first so the random stream never depends on timing.
const customers = Array.from({ length: N_CUSTOMERS }, (_, i) => ({
  customer_name: `Customer ${i + 1}`,
  email: `c${i + 1}@example.com`,
  city: pick(CITIES),
  credit_limit: Math.round(rand() * 100000) / 100,
  active: rand() > 0.1,
}));
const orders = Array.from({ length: N_ORDERS }, () => {
  const ci = Math.floor(rand() * N_CUSTOMERS);
  const day = 1 + Math.floor(rand() * 365);
  const d = new Date(Date.UTC(2025, 0, day)).toISOString().slice(0, 10);
  return {
    ci,
    doc: {
      order_date: d,
      status: pick(STATUSES),
      items: Array.from({ length: 5 }, (_, k) => ({
        item: `SKU-${1 + Math.floor(rand() * 500)}`,
        qty: 1 + Math.floor(rand() * 10),
        rate: Math.round(rand() * 50000) / 100,
      })),
    },
  };
});

// Refuse a populated target: a second seed would double the data and break parity.
const existing = t.unwrapCount(await send(t.count("Bench Customer")));
if (existing > 0) {
  console.error(`[${name}] already has ${existing} customers — run \`make setup-${name}\` for a clean stack first`);
  process.exit(1);
}

const t0 = Date.now();
console.log(`[${name}] ${N_CUSTOMERS} customers`);
const ids = await pool(customers, async (c) => t.idOf((await send(t.insert("Bench Customer", c))).data));
console.log(`[${name}] ${N_ORDERS} orders × 5 items`);
await pool(orders, async (o) => send(t.insert("Bench Order", { customer: ids[o.ci], ...o.doc })));
console.log(`[${name}] seeded in ${((Date.now() - t0) / 1000).toFixed(1)}s (${retries} write conflicts retried)`);
