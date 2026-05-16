.DEFAULT_GOAL := help
SHELL         := /usr/bin/env bash

# ── Path shortcuts ─────────────────────────────────────────────────────────────
TF_LOCAL       := infra/terraform/envs/local
KUBECONFIG_LOCAL ?= $(HOME)/.kube/sentinelops-local.yaml

# ── Help ──────────────────────────────────────────────────────────────────────
.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

# ===== LOCAL CLUSTER ===========================================================

.PHONY: up-local
up-local: ## Provision local k3d cluster via Terraform
	@echo "▶ Provisioning local k3d cluster…"
	@cd $(TF_LOCAL) && terraform init -upgrade && terraform apply -auto-approve
	@echo ""
	@echo "✅ Cluster ready. Run 'make status-local' to verify."
	@echo "   export KUBECONFIG=$(KUBECONFIG_LOCAL)"

.PHONY: down-local
down-local: ## Destroy local k3d cluster
	@echo "▶ Destroying local k3d cluster…"
	@cd $(TF_LOCAL) && terraform destroy -auto-approve
	@echo "✅ Cluster destroyed."

.PHONY: reset-local
reset-local: down-local up-local ## Destroy and recreate the local cluster

.PHONY: status-local
status-local: ## Show local cluster status
	@echo "=== Terraform outputs ==="
	@cd $(TF_LOCAL) && terraform output
	@echo ""
	@echo "=== Cluster nodes ==="
	@KUBECONFIG=$(KUBECONFIG_LOCAL) kubectl get nodes
	@echo ""
	@echo "=== All pods ==="
	@KUBECONFIG=$(KUBECONFIG_LOCAL) kubectl get pods -A

.PHONY: kubeconfig-local
kubeconfig-local: ## Print the export command for local kubeconfig
	@echo "export KUBECONFIG=$(KUBECONFIG_LOCAL)"

.PHONY: smoke-test-local
smoke-test-local: ## Push a test image and deploy to verify registry + cluster
	@KUBECONFIG=$(KUBECONFIG_LOCAL) bash scripts/smoke-test-local.sh

# ===== TERRAFORM UTILITIES ====================================================

.PHONY: lint-tf
lint-tf: ## Check Terraform formatting (no changes written)
	@echo "▶ Checking Terraform formatting…"
	@terraform fmt -check -recursive infra/terraform/
	@echo "✅ All .tf files are formatted correctly."

.PHONY: fmt-tf
fmt-tf: ## Format all Terraform files in-place
	@echo "▶ Formatting Terraform files…"
	@terraform fmt -recursive infra/terraform/
	@echo "✅ Done."

.PHONY: validate-local
validate-local: ## Run terraform validate on envs/local
	@echo "▶ Validating infra/terraform/envs/local…"
	@cd $(TF_LOCAL) && terraform init -backend=false -input=false > /dev/null && terraform validate
	@echo "✅ Validation passed."

# ===== VERIFICATION ===========================================================

.PHONY: check-env
check-env: ## Run Day 0 environment verification
	@bash scripts/verify-environment.sh

.PHONY: check-day1
check-day1: ## Run Day 1 verification checklist
	@bash scripts/day-1-check.sh
