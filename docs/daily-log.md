# SentinelOps Daily Log

This file tracks daily progress, blockers, and time spent across the 20-day build.

---

## Day 0 — Environment Bootstrap (2026-05-16)

**Goal:** All tools installed, accounts ready, repo bootstrapped.

### Completed
- [ ] WSL2 + Docker Desktop verified
- [ ] All CLI tools installed (see scripts/verify-environment.sh output)
- [ ] AWS account created, MFA enabled, IAM user `sentinelops-dev` configured
- [ ] AWS budget alerts set at $25/$50/$75/$90
- [ ] `aws sts get-caller-identity` returns expected account
- [ ] Anthropic API key in ~/.bashrc, test curl returns response
- [ ] GitHub CLI authenticated, repo pushed
- [ ] Smoke test: k3d cluster create → nginx pod → delete cluster works
- [ ] Kaggle API token saved to ~/.kaggle/kaggle.json

### Time spent
X hours

### Blockers
None / [list]

---

## Day 1 — Local k3d Cluster via Terraform (2026-05-16)

**Goal:** Reproducible local Kubernetes cluster provisioned by Terraform.

### Completed
- [ ] local-cluster Terraform module written (main.tf, variables.tf, outputs.tf, versions.tf, README.md)
- [ ] envs/local environment configured (main.tf, versions.tf, backend.tf, README.md)
- [ ] Makefile with up-local, down-local, reset-local, status-local, smoke-test-local targets
- [ ] Smoke test script validates registry + cluster
- [ ] `terraform fmt -check` passes
- [ ] `terraform validate` passes
- [ ] Cluster recreation cycle works 3 times without error
- [ ] Day 1 verification script passes

### Time spent
X hours

### Blockers
None / [list]

### Tomorrow
Day 2: Foundation layer — MinIO + Postgres + Redpanda via Helm

---

## Day 2 — Foundation Layer (2026-05-16)

**Goal:** MinIO + Postgres + Redpanda + cert-manager running via Terraform-managed Helm.

### Completed
- [ ] helm-platform Terraform module created
- [ ] All Helm values files (minio.yaml, postgresql.yaml, redpanda.yaml, cert-manager.yaml)
- [ ] Local env updated to invoke helm-platform module
- [ ] All 6 namespaces created with proper labels
- [ ] MinIO running with 3 pre-created buckets
- [ ] Postgres running with 3 pre-created databases
- [ ] Redpanda running with 4 pre-created topics
- [ ] cert-manager running with CRDs installed
- [ ] Fraud dataset uploaded to MinIO datasets/ bucket
- [ ] Day 2 verification script passes

### Time spent
X hours

### Cluster RAM at end of day
~XGB (target: <4GB)

### Blockers
None / [list]

## Day 3 — MLflow + Kubeflow Pipelines (2026-05-19)

**Goal:** MLflow + Kubeflow Pipelines standalone v2.4.0 installed and verified.

### Task 1 — MLflow (completed in prior session)
- [x] Plain K8s Deployment (burakince/mlflow:2.1.1)
- [x] Verified: GET /health → 200, /version → 2.1.1

### Task 2 — Kubeflow Pipelines Standalone v2.4.0
- [x] Upgraded from 2.3.0 → 2.4.0 (gcr.io shutdown March 2025 killed all 2.3.0 images)
- [x] Lean kustomize overlay (infra/kustomize/kubeflow-pipelines/) — no bundled MinIO
- [x] Platform MinIO routed via ExternalName service (minio-service → minio.platform.svc.cluster.local)
- [x] All 13 KFP deployments Available
- [x] Tutorial pipeline `[Tutorial] Data passing in python components` — **Succeeded**
- [x] KFP UI accessible at http://localhost:8888
- [x] Cluster RAM after KFP: ~3.8 GB (target <8 GB)

### Hard-won fixes (Day 3 lessons)
1. **gcr.io shutdown (March 2025)** — KFP 2.3.0 images all deleted. Upgraded to 2.4.0 (ghcr.io).
2. **platform-agnostic bundled MinIO** — `gcr.io/ml-pipeline/minio:RELEASE.2019-08-14T20-37-41Z` deleted. Used lean kustomize overlay that routes to platform MinIO via ExternalName.
3. **OBJECTSTORECONFIG_HOST missing** — ExternalName services don't inject K8s env vars. Patched ml-pipeline deployment with explicit `OBJECTSTORECONFIG_HOST=minio-service.kubeflow.svc.cluster.local`.
4. **argoexec init container** — `gcr.io/ml-pipeline/argoexec:v3.4.17-license-compliance` deleted. Loaded `quay.io/argoproj/argoexec:v3.4.17` into k3d nodes via `docker cp + ctr images import` after clearing corrupt partial imports. Also patched workflow-controller-configmap executor image.
5. **Terraform depends_on** — `make kfp-apply` triggered postgresql Helm upgrade (timeout). Switched kfp-apply to use `install-kfp.sh` directly (kubectl apply, no Terraform).
6. **Windows/WSL2 split** — Cursor edits Windows path; kubectl runs in WSL2 ~/sentinelops. Sync via `cp /mnt/c/...` pattern. Added .claude/ to .gitignore.
7. **Docker Desktop hung** — k3d image import and docker exec hung for 3+ hours. Fix: kill all docker processes via Task Manager + wsl --shutdown + laptop restart.

### Makefile targets added
- `make kfp-apply` — kubectl-based install (no Terraform)
- `make kfp-down` / `kfp-up` — scale KFP to 0/1
- `make kfp-status` — show pods + RAM
- `make port-forward-kfp` — port-forward UI to 8888

### Time spent
~10 hours (majority on gcr.io image debugging)

### Cluster RAM after KFP
~3.8 GB total (target <8 GB) ✅

### Tomorrow
Day 4: First ML pipeline — LightGBM fraud detection
