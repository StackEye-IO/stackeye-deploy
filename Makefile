# Makefile for StackEye Helm charts

.PHONY: help lint template test install uninstall package publish deps clean

HELM := helm
HELMFILE := helmfile
CT := ct

# Default environment
ENV ?= dev

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

lint: ## Lint all charts
	$(CT) lint --config ct.yaml

lint-api: ## Lint stackeye-api chart
	$(HELM) lint charts/stackeye-api

lint-worker: ## Lint stackeye-worker chart
	$(HELM) lint charts/stackeye-worker

lint-web: ## Lint stackeye-web chart
	$(HELM) lint charts/stackeye-web

template: ## Template all charts (dry-run)
	$(HELM) template stackeye-api charts/stackeye-api -f charts/stackeye-api/values-$(ENV).yaml
	@echo "---"
	$(HELM) template stackeye-worker charts/stackeye-worker -f charts/stackeye-worker/values-$(ENV).yaml
	@echo "---"
	$(HELM) template stackeye-web charts/stackeye-web -f charts/stackeye-web/values-$(ENV).yaml

template-api: ## Template stackeye-api chart
	$(HELM) template stackeye-api charts/stackeye-api -f charts/stackeye-api/values-$(ENV).yaml

template-worker: ## Template stackeye-worker chart
	$(HELM) template stackeye-worker charts/stackeye-worker -f charts/stackeye-worker/values-$(ENV).yaml

template-web: ## Template stackeye-web chart
	$(HELM) template stackeye-web charts/stackeye-web -f charts/stackeye-web/values-$(ENV).yaml

deps: ## Update chart dependencies
	$(HELM) dependency update charts/stackeye-api
	$(HELM) dependency update charts/stackeye-worker
	$(HELM) dependency update charts/stackeye-web

install: ## Install all charts using helmfile
	$(HELMFILE) -e $(ENV) apply

uninstall: ## Uninstall all charts using helmfile
	$(HELMFILE) -e $(ENV) destroy

diff: ## Show diff of changes using helmfile
	$(HELMFILE) -e $(ENV) diff

package: ## Package all charts
	mkdir -p .packages
	$(HELM) package charts/stackeye-api -d .packages/
	$(HELM) package charts/stackeye-worker -d .packages/
	$(HELM) package charts/stackeye-web -d .packages/

publish: package ## Publish charts to Harbor OCI registry
	for pkg in .packages/*.tgz; do \
		$(HELM) push $$pkg oci://harbor.support.tools/stackeye/charts; \
	done

clean: ## Clean build artifacts
	rm -rf .packages
	rm -rf charts/*/charts
	rm -rf charts/*/*.lock
