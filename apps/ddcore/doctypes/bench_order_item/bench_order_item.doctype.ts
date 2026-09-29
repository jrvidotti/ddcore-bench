import { defineDoctype } from "@ddcore/sdk";

export default defineDoctype({
  name: "Bench Order Item",
  module: "Bench",
  label: "Bench Order Item",
  isChild: true,
  fields: [
    { fieldname: "item", fieldtype: "Data", label: "Item", reqd: true, inListView: true },
    { fieldname: "qty", fieldtype: "Float", label: "Qty", reqd: true, inListView: true },
    { fieldname: "rate", fieldtype: "Currency", label: "Rate", reqd: true, inListView: true },
    { fieldname: "amount", fieldtype: "Currency", label: "Amount", readOnly: true, inListView: true },
  ],
});
