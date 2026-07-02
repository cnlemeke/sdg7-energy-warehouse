# Docker:       make up && make all             (full data in data/raw/WB_SE4ALL.csv)
# Local psql:   make all PSQL="psql -d se4all -v ON_ERROR_STOP=1"
# Sample data:  make all CSV=data/sample/WB_SE4ALL_sample.csv
#
# Full-data runs write to results/ and figures/. A run on any other CSV writes to
# results/sample and figures/sample so the committed full-data results are never overwritten.
CSV ?= data/raw/WB_SE4ALL.csv
ifeq ($(CSV),data/raw/WB_SE4ALL.csv)
OUT ?= results
FIG ?= figures
else
OUT ?= results/sample
FIG ?= figures/sample
endif
PYTHON ?= python3
PSQL ?= docker compose exec -T db psql -U postgres -d se4all -v ON_ERROR_STOP=1

.PHONY: up down all schema load transform index dq views analytics advanced marts perf export figures crosscheck compare psql
up:        ; docker compose up -d --wait
down:      ; docker compose down -v
schema:    ; $(PSQL) -f sql/01_schema.sql
load:      ; $(PSQL) -v csv_path="'$(CSV)'" -f sql/02_load_staging.sql
transform: ; $(PSQL) -f sql/03_transform_load_dw.sql
index:     ; $(PSQL) -f sql/04_constraints_indexes.sql
views:     ; $(PSQL) -f sql/06_views.sql
dq:        ; $(PSQL) -f sql/05_data_quality.sql -c "SELECT dq.assert_clean();"
analytics: ; $(PSQL) -f sql/07_analytics.sql
advanced:  ; $(PSQL) -f sql/08_postgres_advanced.sql
marts:     ; $(PSQL) -f sql/09_mart_objects.sql
perf:      ; $(PSQL) -f sql/10_performance.sql
export:    ; mkdir -p $(OUT) && $(PSQL) -v out_dir=$(OUT) -f sql/11_export_results.sql
figures:   ; $(PYTHON) python/make_figures.py --results $(OUT) --figures $(FIG)
crosscheck:; $(PYTHON) tests/crosscheck.py $(CSV) --write-results --out $(OUT)
compare:   ; $(PYTHON) tests/crosscheck.py $(CSV) --write-results --out $(OUT)/oracle && $(PYTHON) tests/compare_postgres.py $(OUT)/oracle --psql "$(PSQL)"
psql:      ; docker compose exec db psql -U postgres -d se4all
# order matters: dq needs the fact table, views are needed by marts/analytics
all: schema load transform index dq views analytics advanced marts perf export figures
