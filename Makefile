# SAS Viya kubectl Tests Makefile

.PHONY: help setup test clean report

ENVIRONMENT ?= dev
NAMESPACE ?= sas-viya
TEST_TYPE ?= smoke
PYTHON := python3
REPORT_FORMAT ?= html

help:
	@echo "SAS Viya kubectl Test Suite"
	@echo ""
	@echo "Available targets:"
	@echo "  setup       - Setup testing environment and prerequisites"
	@echo "  test        - Run tests (use TEST_TYPE=smoke|full|component)"
	@echo "  report      - Generate test report"
	@echo "  monitor     - Start continuous monitoring"
	@echo "  clean       - Clean up resources and tunnels"
	@echo ""
	@echo "Variables:"
	@echo "  ENVIRONMENT - Target environment (dev|staging|prod)"
	@echo "  NAMESPACE   - Kubernetes namespace"
	@echo "  TEST_TYPE   - Type of test to run"

setup:
	@echo "Setting up test environment..."
	@./scripts/setup/install-prerequisites.sh
	@./scripts/setup/setup-bastion-tunnel.sh $(ENVIRONMENT)
	@./scripts/setup/setup-kubectl-context.sh $(ENVIRONMENT)
	@./scripts/setup/verify-setup.sh

test-smoke:
	@echo "Running smoke tests..."
	@./tests/scenarios/smoke_test.sh $(NAMESPACE)

test-full:
	@echo "Running full validation..."
	@./tests/scenarios/full_validation.sh $(NAMESPACE)

test-components:
	@echo "Running component tests..."
	@./tests/kubectl/components/test_cas_server.sh $(NAMESPACE)
	@./tests/kubectl/components/test_microservices.sh $(NAMESPACE)

test-python:
	@echo "Running Python integration tests..."
	@$(PYTHON) -m pytest tests/python/ -v --namespace=$(NAMESPACE)

test: test-$(TEST_TYPE)

monitor:
	@echo "Starting continuous monitoring..."
	@./tests/kubectl/monitoring/continuous_monitor.sh $(NAMESPACE) --watch

report:
	@echo "Generating test report..."
	@./scripts/utils/report-generator.sh $(REPORT_FORMAT)

clean:
	@echo "Cleaning up..."
	@./scripts/teardown/cleanup-tunnels.sh
	@./scripts/teardown/cleanup-resources.sh

install:
	@pip install -r requirements.txt
	@pip install -e .

docker-build:
	@docker build -f docker/Dockerfile -t sas-viya-kubectl-tests:latest .

docker-test:
	@docker-compose -f docker/docker-compose.yml up --abort-on-container-exit
