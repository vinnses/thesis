MAIN_TEX ?= tex/main.tex
MAIN_TEX_DIR = $(abspath $(patsubst %/,%,$(dir $(MAIN_TEX))))
MAIN_TEX_BASENAME = $(notdir $(basename $(MAIN_TEX)))
MAIN_TEX_LOG = $(MAIN_TEX_DIR)/$(MAIN_TEX_BASENAME).log
BUILD_REPORT ?= build-report.md
LATEX_SEARCH_ENV = TEXINPUTS="$(MAIN_TEX_DIR)//:$$TEXINPUTS:" BIBINPUTS="$(MAIN_TEX_DIR)//:$$BIBINPUTS:" BSTINPUTS="$(MAIN_TEX_DIR)//:$$BSTINPUTS:"
LATEXMK ?= latexmk
LATEXMK_FLAGS ?= -interaction=nonstopmode -file-line-error
LATEX_BUILD ?= latexctl/bin/latexctl build
BUILD_DEPS ?= latexmk tlmgr
LINT_DEPS ?= chktex
FORMAT_DEPS ?= latexindent

.PHONY: help check-env sync deps build pdf watch clean lint format ci zip test

help:
	@echo "Available targets:"
	@echo "  make sync        - sync tlmgr user packages from tex/ sources"
	@echo "  make deps        - backward-compatible alias of sync"
	@echo "  make test        - run shell-based regression tests"
	@echo "  make zip         - create an export zip from tex/ sources"
	@echo "  make check-env   - validate build tools are installed"
	@echo "  make build       - clean aux files in tex/, sync dependencies, keep only current+previous PDF, and run the smart build"
	@echo "  make pdf         - compile MAIN_TEX directly with latexmk and preserve intermediates for faster edits"
	@echo "  make watch       - continuous compilation (-pvc)"
	@echo "  make clean       - remove LaTeX auxiliary files and keep generated PDFs"
	@echo "  make lint        - run chktex if available"
	@echo "  make format      - format MAIN_TEX with latexindent"
	@echo "  make ci          - run deps, check-env, lint, and build"

sync:
	latexctl/bin/latexctl sync

deps: sync

zip:
	latexctl/bin/latexctl ziptex

test:
	bash latexctl/tests/test_sync_tlmgr.sh
	bash latexctl/tests/test_latexctl.sh

check-env:
	@for bin in $(BUILD_DEPS); do \
		command -v "$$bin" >/dev/null 2>&1 || { echo "Missing dependency: $$bin"; exit 1; }; \
	done

build: check-env
	LATEXMK="$(LATEXMK)" $(LATEX_BUILD) $(MAIN_TEX) $(LATEXMK_FLAGS)

pdf: check-env
	@set +e; \
	$(LATEX_SEARCH_ENV) $(LATEXMK) -cd -pdf $(LATEXMK_FLAGS) $(MAIN_TEX); \
	status=$$?; \
	report_status=success; \
	if [ $$status -ne 0 ]; then report_status=failure; fi; \
	latexctl/bin/latexctl report-build --status "$$report_status" --log "$(MAIN_TEX_LOG)" --output "$(BUILD_REPORT)" --output-dir .latex-errors; \
	report_exit=$$?; \
	if [ $$report_exit -ne 0 ]; then exit $$report_exit; fi; \
	exit $$status

watch: deps check-env
	$(LATEX_SEARCH_ENV) $(LATEXMK) -cd -pdf -pvc $(LATEXMK_FLAGS) $(MAIN_TEX)

clean:
	@test ! -d tex || find tex -type f \( \
		-name '*.aux' -o \
		-name '*.bbl' -o \
		-name '*.bcf' -o \
		-name '*.blg' -o \
		-name '*.fdb_latexmk' -o \
		-name '*.fls' -o \
		-name '*.lof' -o \
		-name '*.log' -o \
		-name '*.lot' -o \
		-name '*.out' -o \
		-name '*.run.xml' -o \
		-name '*.synctex.gz' -o \
		-name '*.toc' -o \
		-name '*.xdv' -o \
		-name 'missfont.log' \
	\) -delete

lint:
	@if command -v "$(LINT_DEPS)" >/dev/null 2>&1; then \
		"$(LINT_DEPS)" -q -n1 -n2 -n3 $(MAIN_TEX); \
	else \
		echo "Error: $(LINT_DEPS) is not installed."; \
		exit 1; \
	fi

format:
	@if command -v "$(FORMAT_DEPS)" >/dev/null 2>&1; then \
		"$(FORMAT_DEPS)" -w $(MAIN_TEX); \
	else \
		echo "Error: $(FORMAT_DEPS) is not installed."; \
		exit 1; \
	fi

ci: deps check-env lint build
