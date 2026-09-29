// The one place where ddcore and Frappe differ on the wire. Everything else
// (scenarios, seed) speaks through these functions, so a scenario is written
// once and runs unchanged against either target. Plain ES module: it is loaded
// by k6 and by Node (seed/). See ddcore docs/frappe-rest-gap-analysis.md.

const TARGETS = {
  ddcore: {
    base: "http://localhost:8101",
    idField: "id",
    method: (name) => `/api/method/benchapp.services.orders.${name}`,
    unwrapMethod: (body) => body.data,
    listParams: (start, limit) => `start=${start}&limit=${limit}`,
    check: (v) => v, // booleans
    submit: (id) => ({ method: "POST", path: `/api/resource/Bench%20Order/${id}/submit`, body: null }),
  },
  frappe: {
    base: "http://localhost:8102",
    idField: "name",
    method: (name) => `/api/method/benchapp.api.${name}`,
    unwrapMethod: (body) => body.message,
    listParams: (start, limit) => `limit_start=${start}&limit_page_length=${limit}`,
    check: (v) => (v ? 1 : 0),
    // Frappe submits when a save moves docstatus from 0 to 1
    submit: (id) => ({ method: "PUT", path: `/api/resource/Bench%20Order/${id}`, body: { docstatus: 1 } }),
  },
};

export function target(name, overrides = {}) {
  const t = TARGETS[name];
  if (!t) throw new Error(`unknown target "${name}" (ddcore | frappe)`);
  const base = overrides.base || t.base;
  const auth = `token ${overrides.token}`;
  const headers = { Authorization: auth, "Content-Type": "application/json", Accept: "application/json" };
  const res = (dt) => `/api/resource/${encodeURIComponent(dt)}`;

  return {
    name,
    base,
    headers,
    idField: t.idField,
    idOf: (doc) => doc[t.idField],
    unwrapMethod: t.unwrapMethod,

    // Each builder returns { method, url, body } — the caller performs the request
    // with its own HTTP client (k6/http or fetch).
    ping: () => ({ method: "GET", url: base + t.method("ping") }),
    summary: (customer) => ({ method: "GET", url: `${base}${t.method("summary")}?customer=${encodeURIComponent(customer)}` }),
    get: (dt, id) => ({ method: "GET", url: `${base}${res(dt)}/${encodeURIComponent(id)}` }),
    list: (dt, { fields = [], filters, orderBy, start = 0, limit = 20 } = {}) => {
      const f = fields.map((x) => (x === "id" ? t.idField : x));
      let q = `${t.listParams(start, limit)}&fields=${encodeURIComponent(JSON.stringify(f))}`;
      if (filters) q += `&filters=${encodeURIComponent(JSON.stringify(filters))}`;
      if (orderBy) q += `&order_by=${encodeURIComponent(orderBy)}`;
      return { method: "GET", url: `${base}${res(dt)}?${q}` };
    },
    insert: (dt, doc) => ({ method: "POST", url: base + res(dt), body: JSON.stringify(normalize(doc, t)) }),
    update: (dt, id, patch) => ({ method: "PUT", url: `${base}${res(dt)}/${encodeURIComponent(id)}`, body: JSON.stringify(normalize(patch, t)) }),
    submit: (id) => {
      const s = t.submit(encodeURIComponent(id));
      return { method: s.method, url: base + s.path, body: s.body ? JSON.stringify(s.body) : null };
    },
    count: (dt) =>
      name === "ddcore"
        ? { method: "GET", url: `${base}/api/count/${encodeURIComponent(dt)}` }
        : { method: "GET", url: `${base}/api/method/frappe.client.get_count?doctype=${encodeURIComponent(dt)}` },
    unwrapCount: (body) => (name === "ddcore" ? body.data : body.message),
  };
}

// Check fields travel as booleans to ddcore and 0/1 to Frappe.
function normalize(doc, t) {
  const out = {};
  for (const [k, v] of Object.entries(doc)) out[k] = typeof v === "boolean" ? t.check(v) : v;
  return out;
}
