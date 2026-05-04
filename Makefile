.PHONY: help build build-release test test-parallel tools check format lint clean start stop package check-test ci all e2e-test

TOOLS_BIN_DIR := $(shell swift build --package-path Tools --show-bin-path 2>/dev/null)
SWIFTFORMAT := $(TOOLS_BIN_DIR)/swiftformat
SWIFTLINT := $(TOOLS_BIN_DIR)/swiftlint

help: ## Display available make targets
	@awk 'BEGIN {FS=":.*##"; printf "\nUsage: make <target>\n\nTargets:\n"} /^[a-zA-Z0-9_\-]+:.*##/ {printf "  %-16s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

## Build targets

build: ## Build the project (debug)
	@if [ -n "$$VERBOSE" ]; then \
		swift build; \
	else \
		. ./hack/run_silent.sh && run_silent "Build (debug)" "swift build"; \
	fi

build-release: ## Build the project (release)
	@if [ -n "$$VERBOSE" ]; then \
		swift build -c release; \
	else \
		. ./hack/run_silent.sh && run_silent "Build (release)" "swift build -c release"; \
	fi

## Test targets

test: ## Run unit tests (quiet output)
	@if [ -n "$$VERBOSE" ]; then \
		swift test; \
	else \
		$(MAKE) test-quiet; \
	fi

test-quiet:
	@. ./hack/run_silent.sh && print_main_header "Running Tests"
	@. ./hack/run_silent.sh && print_header "GCalNotifier" "Unit tests"
	@. ./hack/run_silent.sh && run_silent_with_test_count "Unit tests passed" "swift test"

test-parallel: ## Run tests in parallel (quiet output)
	@if [ -n "$$VERBOSE" ]; then \
		swift test --parallel; \
	else \
		. ./hack/run_silent.sh && print_main_header "Running Tests (Parallel)" && \
		print_header "GCalNotifier" "Unit tests" && \
		run_silent_with_test_count "Unit tests passed" "swift test --parallel"; \
	fi

e2e-test: ## Run E2E test scripts sequentially (interactive)
	@echo "=== Running E2E Tests ==="
	@echo "These tests are interactive and require manual verification."
	@echo "Log output: ~/Library/Logs/gcal-notifier/e2e-tests.log"
	@echo ""
	@./Scripts/e2e/test_oauth_flow.sh && \
	./Scripts/e2e/test_sync_cycle.sh && \
	./Scripts/e2e/test_alert_timing.sh && \
	./Scripts/e2e/test_offline_resilience.sh && \
	echo "" && echo "=== All E2E Tests Passed ===" || \
	(echo "" && echo "=== E2E Tests Failed ===" && exit 1)

## Check targets (formatting and linting)

tools: ## Build pinned development tools
	@if [ -n "$$VERBOSE" ]; then \
		swift build --package-path Tools --product swiftformat --product swiftlint; \
	else \
		. ./hack/run_silent.sh && run_silent "Build pinned tools" "swift build --package-path Tools --product swiftformat --product swiftlint"; \
	fi

check: tools ## Run format check and lint (quiet output)
	@if [ -n "$$VERBOSE" ]; then \
		$(SWIFTFORMAT) . --lint && $(SWIFTLINT) lint --strict; \
	else \
		$(MAKE) check-quiet; \
	fi

check-quiet:
	@. ./hack/run_silent.sh && print_main_header "Running Checks"
	@. ./hack/run_silent.sh && print_header "GCalNotifier" "Format check"
	@. ./hack/run_silent.sh && run_with_quiet "Format" "$(SWIFTFORMAT) . --lint"
	@. ./hack/run_silent.sh && print_header "GCalNotifier" "Lint"
	@. ./hack/run_silent.sh && run_with_quiet "Lint" "$(SWIFTLINT) lint --strict"

format: tools ## Auto-format code with swiftformat
	@if [ -n "$$VERBOSE" ]; then \
		$(SWIFTFORMAT) .; \
	else \
		. ./hack/run_silent.sh && run_silent "Formatting code" "$(SWIFTFORMAT) ."; \
	fi

lint: tools ## Run swiftlint with auto-fix
	@if [ -n "$$VERBOSE" ]; then \
		$(SWIFTLINT) lint --fix --strict; \
	else \
		. ./hack/run_silent.sh && run_silent "Linting code" "$(SWIFTLINT) lint --fix --strict"; \
	fi

## Combined targets

check-test: ci ## Run the same gate as CI

ci: ## Run the canonical local/CI gate
	@$(MAKE) check
	@$(MAKE) build
	@$(MAKE) build-release
	@$(MAKE) test-parallel

all: ## Run format, lint, and tests
	@$(MAKE) format
	@$(MAKE) lint
	@$(MAKE) test

## App targets

start: ## Build, package, and run the app
	@./Scripts/kill_app.sh 2>/dev/null || true
	@$(MAKE) package
	@open dist/GCalNotifier.app

stop: ## Stop running app instances
	@./Scripts/kill_app.sh

package: ## Package app as .app bundle (use RELEASE=1 for release build)
	@if [ -n "$$RELEASE" ]; then \
		./Scripts/package_app.sh release; \
	else \
		./Scripts/package_app.sh debug; \
	fi

## Cleanup

clean: ## Remove build artifacts
	@if [ -n "$$VERBOSE" ]; then \
		swift package clean && rm -rf .build; \
	else \
		. ./hack/run_silent.sh && run_silent "Cleaning" "swift package clean && rm -rf .build"; \
	fi
