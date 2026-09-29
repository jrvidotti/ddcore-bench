# ddcore × Frappe benchmark. Every target writes its output to the terminal and
# to logs/<target>-<timestamp>.log.   make help
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -ec
.DEFAULT_GOAL := help

TS      := $(shell date +%Y%m%d-%H%M%S)
LOGDIR  := logs
LOG      = $(LOGDIR)/$@$(LOGTAG)-$(TS).log
ENV     := set -a; [ -f .env.bench ] && . ./.env.bench; set +a;
# run a command, tee'ing stdout+stderr into this target's log
RUN      = mkdir -p $(LOGDIR); echo "→ $(LOG)"; ( $(1) ) 2>&1 | tee $(LOG)

# ddcore | frappe, for the per-target k6/stack targets
TARGET  ?= ddcore
COMPOSE  = docker compose -f compose/docker-compose.$(strip $(1)).yml

# seed size and k6 knobs (override: make seed-ddcore ORDERS=100000)
CUSTOMERS ?= 1000
ORDERS    ?= 10000
CONC      ?= 16
RATE      ?= 100
DURATION  ?= 2m
OP        ?= get

.PHONY: help tools setup-ddcore setup-frappe setup seed-ddcore seed-frappe seed \
        start stop down status phase1 all smoke ramp rate soak crud logs-app clean-logs

help: ## this list
	@grep -hE '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo; echo "  Vars: TARGET=$(strip $(TARGET)) CUSTOMERS=$(CUSTOMERS) ORDERS=$(ORDERS) CONC=$(CONC) RATE=$(RATE) DURATION=$(DURATION) OP=$(OP)"

tools: ## install k6 and oha (brew)
	$(call RUN, brew install k6 oha)

# ---- stacks -------------------------------------------------------------------

setup-ddcore: ## ddcore stack from scratch (wipes data), boot time, API key
	$(call RUN, scripts/setup.sh ddcore)

setup-frappe: ## Frappe stack from scratch (wipes data), boot time, API key
	$(call RUN, scripts/setup.sh frappe)

setup: setup-ddcore setup-frappe ## both stacks from scratch

seed-ddcore: ## seed ddcore (CUSTOMERS, ORDERS, CONC)
	$(call RUN, $(ENV) $(call COMPOSE,ddcore) start && scripts/wait-ready.sh ddcore && node seed/seed.js ddcore --customers $(CUSTOMERS) --orders $(ORDERS) --concurrency $(CONC))

seed-frappe: ## seed Frappe (CUSTOMERS, ORDERS, CONC)
	$(call RUN, $(ENV) $(call COMPOSE,frappe) start && scripts/wait-ready.sh frappe && node seed/seed.js frappe --customers $(CUSTOMERS) --orders $(ORDERS) --concurrency $(CONC))

seed: ## seed both, one stack up at a time
	$(MAKE) stop TARGET=frappe; $(MAKE) seed-ddcore; $(MAKE) stop TARGET=ddcore
	$(MAKE) seed-frappe; $(MAKE) stop TARGET=frappe

start: ## start TARGET's stack (and stop the other)
	@other=$$([ "$(strip $(TARGET))" = ddcore ] && echo frappe || echo ddcore); \
	  $(call COMPOSE,$$other) stop >/dev/null 2>&1 || true
	$(call COMPOSE,$(TARGET)) start
	scripts/wait-ready.sh $(strip $(TARGET))

stop: ## stop TARGET's stack (data kept)
	$(call COMPOSE,$(TARGET)) stop

down: ## remove TARGET's stack AND its data
	$(call COMPOSE,$(TARGET)) down -v

status: ## containers and resource use of both stacks
	@docker ps -a --filter name=bench- --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
	@ids=$$(docker ps -q --filter name=bench-); [ -z "$$ids" ] || docker stats --no-stream $$ids

logs-app: ## follow TARGET's app container logs
	$(call COMPOSE,$(TARGET)) logs -f app

# ---- phase 1 ------------------------------------------------------------------

phase1: ## Phase 1 on both targets (oha) → results/<date>-<sha>/REPORT.md
	$(call RUN, scripts/run-phase1.sh)

# ---- phase 2 (k6, against TARGET; start it first with make start) ---------------

# the log name carries the target (and the op): logs/crud-frappe-insert-<ts>.log
smoke ramp rate soak: LOGTAG = -$(strip $(TARGET))
crud: LOGTAG = -$(strip $(TARGET))-$(OP)

smoke: ## k6 mix, 1 VU × 10 iterations: checks must be 100%
	$(call RUN, scripts/k6.sh $(strip $(TARGET)) k6/scenarios/mix.js)

ramp: ## k6 mix, VUs 1 → 200: find the knee
	$(call RUN, scripts/k6.sh $(strip $(TARGET)) k6/scenarios/mix.js -e PROFILE=ramp)

rate: ## k6 mix at a fixed RATE req/s for DURATION
	$(call RUN, scripts/k6.sh $(strip $(TARGET)) k6/scenarios/mix.js -e PROFILE=rate -e RATE=$(RATE) -e DURATION=$(DURATION))

soak: ## k6 mix at RATE for 30m (override DURATION)
	$(call RUN, scripts/k6.sh $(strip $(TARGET)) k6/scenarios/mix.js -e PROFILE=soak -e RATE=$(RATE) $(if $(filter command line,$(origin DURATION)),-e DURATION=$(DURATION)))

crud: ## k6 one operation (OP=get|list|insert|submit|update|summary|ping) at RATE
	$(call RUN, scripts/k6.sh $(strip $(TARGET)) k6/scenarios/crud.js -e OP=$(OP) -e PROFILE=rate -e RATE=$(RATE) -e DURATION=$(DURATION))

all: ## EVERYTHING, seeded targets required: phase 1 + all k6 runs (~2h) → results/full-<ts>/
	$(call RUN, scripts/run-all.sh)

clean-logs: ## delete logs/
	rm -rf $(LOGDIR)
