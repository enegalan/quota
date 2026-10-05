# Quota
#
# The toolchain is Homebrew based. Run `make bootstrap` once, then `make verify`
# before every commit: lint, tests, bundle, signature check.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

BUILD_CONFIGURATION ?= debug
BUNDLE := .build/Quota.app
# `?=` alone is not enough: a secret that is not configured reaches the job as an
# empty string, which is defined, and `-s ""` is a keychain lookup for an identity
# named "". Blank means ad-hoc.
SIGNING_IDENTITY ?=
SIGNING_IDENTITY := $(if $(strip $(SIGNING_IDENTITY)),$(SIGNING_IDENTITY),-)

.PHONY: help bootstrap format format-check lint test build plugins bundle run verify clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Install swiftformat, swiftlint and prettier
	@if ! command -v brew >/dev/null 2>&1; then \
		echo "error: Homebrew is required. Install it from https://brew.sh and re-run 'make bootstrap'." >&2; \
		exit 1; \
	fi
	@command -v swiftformat >/dev/null 2>&1 || brew install swiftformat
	@command -v swiftlint >/dev/null 2>&1 || brew install swiftlint
	@command -v npm >/dev/null 2>&1 || brew install node
	@npm install --global --silent prettier
	@echo "toolchain ready"

format: ## Format Swift and documentation
	swiftformat .
	prettier --write "**/*.{md,json,yml,yaml}"

format-check: ## Fail if anything is unformatted
	swiftformat --lint .
	prettier --check "**/*.{md,json,yml,yaml}"

lint: format-check ## Check formatting and SwiftLint rules
	swiftlint --strict

test: ## Run the test suites. No network access is required or used
	swift test

build: ## Compile without running
	swift build -c $(BUILD_CONFIGURATION)

bundle: ## Assemble Quota.app (set SIGNING_IDENTITY for a distributable build)
	Scripts/bundle.sh --$(BUILD_CONFIGURATION) --sign "$(SIGNING_IDENTITY)"

run: bundle ## Build, then launch
	@open $(BUNDLE)

# The mock provider, built as its own package to prove the boundary holds: it can
# only see PluginKit, so it cannot reach anything the application happens to
# have on its classpath. Its scratch path is outside the repository so its build
# products never end up among ours to lint, format, or commit.
PLUGIN_SCRATCH := $(TMPDIR)/quota-plugin-mock

plugins: ## Build every provider plugin as its own package
	@for plugin in Plugins/*/; do \
		echo "==> $$plugin"; \
		swift build --package-path "$$plugin" --scratch-path "$(PLUGIN_SCRATCH)/$$(basename $$plugin)"; \
	done

verify: lint test plugins bundle ## Everything CI runs
	@echo "verified"

clean: ## Remove build products
	swift package clean
	rm -rf .build
