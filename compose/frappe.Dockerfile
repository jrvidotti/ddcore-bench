# The official frappe_docker production image plus the bench app. Only benchapp
# is installed on the site; ERPNext ships in the image but is never loaded.
ARG FRAPPE_IMAGE=frappe/erpnext:v16.36.1
FROM ${FRAPPE_IMAGE}
COPY --chown=frappe:frappe apps/frappe/benchapp /home/frappe/frappe-bench/apps/benchapp
RUN cd /home/frappe/frappe-bench && (./env/bin/pip install --no-cache-dir -e apps/benchapp || uv pip install --python env/bin/python -e apps/benchapp)
