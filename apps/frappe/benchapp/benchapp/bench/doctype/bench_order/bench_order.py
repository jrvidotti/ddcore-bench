from frappe.model.document import Document


class BenchOrder(Document):
	# Mirrors bench_order.controller.ts: same rule, same rounding.
	def validate(self):
		total = 0
		for row in self.items:
			row.amount = round(row.qty * row.rate, 2)
			total += row.amount
		self.total = round(total, 2)
