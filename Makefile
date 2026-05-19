.DEFAULT_GOAL := help
SHELL         := /usr/bin/env bash

# ── Path shortcuts ─────────────────────────────────────────────────────────────
TF_LOCAL         := infra/terraform/envs/local
KUBECONFIG_LOCAL ?= $(HOME)/.kube/sentinelops-local.yaml

# ── Help ──────────────────────────────────────────────────────────────────────
.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-28s\033[0m %s\n", $$1, $$2}'

# ===== LOCAL CLUSTER ===========================================================

.PHONY: up-local
up-local: ## Provision local k3d cluster only (no Helm charts)
	@echo "▶ Provisioning local k3d cluster…"
	@cd $(TF_LOCAL) && terraform init -upgrade && \
		terraform apply -auto-approve -target=module.local_cluster
	@echo ""
	@echo "✅ Cluster ready. Run 'make status-local' to verify."
	@echo "   export KUBECONFIG=$(KUBECONFIG_LOCAL)"

.PHONY: down-local
down-local: ## Destroy cluster and all foundation services
	@echo "▶ Destroying local cluster and foundation…"
	@cd $(TF_LOCAL) && terraform destroy -auto-approve
	@echo "✅ All resources destroyed."

.PHONY: reset-local
reset-local: down-local up-foundation ## Destroy and recreate cluster + foundation

.PHONY: status-local
status-local: ## Show local cluster nodes and pods
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

# ===== FOUNDATION LAYER ========================================================

.PHONY: up-foundation
up-foundation: up-local ## Provision cluster + all foundation services (MinIO, PG, Redpanda, cert-manager)
	@echo "▶ Provisioning foundation services…"
	@echo "  ⚠  Skips this if foundation pods are already healthy — terraform may replace Helm releases."
	@echo "  ⚠  Use 'cd $(TF_LOCAL) && terraform plan' first when upgrading chart versions."
	@cd $(TF_LOCAL) && terraform apply -auto-approve
	@echo ""
	@echo "✅ Foundation ready. Run 'make status-foundation' to verify."

.PHONY: status-foundation
status-foundation: ## Show foundation services status
	@echo "=== Namespaces ==="
	@KUBECONFIG=$(KUBECONFIG_LOCAL) kubectl get namespaces -l project=sentinelops
	@echo ""
	@echo "=== Helm releases ==="
	@KUBECONFIG=$(KUBECONFIG_LOCAL) helm list -A --kubeconfig $(KUBECONFIG_LOCAL)
	@echo ""
	@echo "=== Platform pods ==="
	@KUBECONFIG=$(KUBECONFIG_LOCAL) kubectl get pods -n platform
	@echo ""
	@echo "=== Redpanda topics ==="
	@bash scripts/list-redpanda-topics.sh || true
	@echo ""
	@echo "=== Postgres databases ==="
	@bash scripts/list-postgres-dbs.sh || true

.PHONY: port-forward-foundation
port-forward-foundation: ## Port-forward MinIO, Postgres, Redpanda console to localhost
	@KUBECONFIG=$(KUBECONFIG_LOCAL) bash scripts/port-forward-foundation.sh

.PHONY: upload-fraud-dataset
upload-fraud-dataset: ## Download Kaggle fraud dataset and upload to MinIO
	@KUBECONFIG=$(KUBECONFIG_LOCAL) bash scripts/upload-fraud-dataset.sh

# ===== KUBEFLOW PIPELINES (DAY 3) ============================================
# Installs via Terraform null_resource (platform-agnostic 2.3.0).
# Does NOT touch platform/* or mlops/mlflow.

.PHONY: kfp-apply
kfp-apply: ## Install KFP via kubectl kustomize (CRDs + lean overlay, ~15–25 min)
	@echo "▶ Installing Kubeflow Pipelines 2.4.0 (namespace kubeflow only)…"
	@KUBECONFIG=$(KUBECONFIG_LOCAL) bash scripts/install-kfp.sh
	@echo "✅ KFP install finished. Run: make kfp-status && make port-forward-kfp"

.PHONY: kfp-down
kfp-down: ## Scale all KFP deployments to 0 (free RAM; keeps PVCs)
	@echo "▶ Scaling kubeflow deployments to 0…"
	@KUBECONFIG=$(KUBECONFIG_LOCAL) kubectl scale deployment --all --replicas=0 -n kubeflow
	@echo "✅ KFP scaled down."

.PHONY: kfp-up
kfp-up: ## Scale all KFP deployments to 1 (after kfp-down)
	@echo "▶ Scaling kubeflow deployments to 1…"
	@KUBECONFIG=$(KUBECONFIG_LOCAL) kubectl scale deployment --all --replicas=1 -n kubeflow
	@echo "✅ KFP scaled up. Wait ~5 min, then: make kfp-status"

.PHONY: kfp-status
kfp-status: ## Show KFP pods and deployments in kubeflow namespace
	@echo "=== kubeflow deployments ==="
	@KUBECONFIG=$(KUBECONFIG_LOCAL) kubectl get deploy -n kubeflow
	@echo ""
	@echo "=== kubeflow pods ==="
	@KUBECONFIG=$(KUBECONFIG_LOCAL) kubectl get pods -n kubeflow

.PHONY: port-forward-kfp
port-forward-kfp: ## Port-forward KFP UI to localhost:8888
	@KUBECONFIG=$(KUBECONFIG_LOCAL) kubectl port-forward svc/ml-pipeline-ui 8888:80 -n kubeflow

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
	@cd $(TF_LOCAL) && terraform init -upgrade -input=false > /dev/null && terraform validate
	@echo "✅ Validation passed."

# ===== VERIFICATION ===========================================================

.PHONY: check-env
check-env: ## Run Day 0 environment verification
	@bash scripts/verify-environment.sh

.PHONY: check-day1
check-day1: ## Run Day 1 verification checklist
	@bash scripts/day-1-check.sh

.PHONY: check-day2
check-day2: ## Run Day 2 verification checklist
	@KUBECONFIG=$(KUBECONFIG_LOCAL) bash scripts/day-2-check.sh
