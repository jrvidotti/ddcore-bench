import { defineDoctype } from "@ddcore/sdk";

export default defineDoctype({
  name: "Bench Customer",
  module: "Bench",
  label: "Bench Customer",
  idGeneration: { series: "CUST-.#####" },
  titleField: "customer_name",
  fields: [
    { fieldname: "customer_name", fieldtype: "Data", label: "Customer name", reqd: true, inListView: true },
    { fieldname: "email", fieldtype: "Data", label: "Email" },
    { fieldname: "city", fieldtype: "Data", label: "City", searchIndex: true },
    { fieldname: "credit_limit", fieldtype: "Currency", label: "Credit limit" },
    { fieldname: "active", fieldtype: "Check", label: "Active", default: true },
  ],
  permissions: [{ role: "System Manager", read: true, write: true, create: true, delete: true }],
});
