import frappe


@frappe.whitelist()
def ping():
	"""No database access: measures the framework and runtime overhead alone."""
	return "pong"


@frappe.whitelist()
def summary(customer):
	"""One aggregate over a customer's orders; mirrors services/orders.ts."""
	row = frappe.db.sql(
		"SELECT count(*), coalesce(sum(total), 0) FROM `tabBench Order` WHERE customer = %s",
		(customer,),
	)[0]
	return {"orders": int(row[0]), "total": float(row[1])}
