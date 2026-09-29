import { defineDoctype } from "@ddcore/sdk";

export default defineDoctype({
  name: "Bench Order",
  module: "Bench",
  label: "Bench Order",
  idGeneration: { series: "ORD-.#######" },
  titleField: "customer",
  submittable: true,
  fields: [
    { fieldname: "customer", fieldtype: "Link", label: "Customer", options: "Bench Customer", reqd: true, inListView: true },
    { fieldname: "order_date", fieldtype: "Date", label: "Order date", reqd: true, searchIndex: true },
    { fieldname: "status", fieldtype: "Select", label: "Status", options: ["Open", "Paid", "Shipped"], default: "Open", searchIndex: true, inListView: true },
    { fieldname: "total", fieldtype: "Currency", label: "Total", readOnly: true, inListView: true },
    { fieldname: "items", fieldtype: "Table", label: "Items", options: "Bench Order Item" },
  ],
  permissions: [{ role: "System Manager", read: true, write: true, create: true, delete: true, submit: true, cancel: true }],
});
