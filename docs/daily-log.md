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

### Tomorrow
Day 3: MLflow + Kubeflow Pipelines (the hard day)

---

## Day 3 — Task 1: MLflow (2026-05-17)

**Goal:** MLflow tracking server + model registry running, backed by Postgres + MinIO.

### Completed
- [x] MLflow 2.1.1 running via plain K8s Deployment (NOT Helm chart)
- [x] Backed by PostgreSQL (mlflow database in platform namespace)
- [x] Artifacts on MinIO (s3://mlflow-artifacts) via S3 protocol
- [x] Health endpoint returns OK
- [x] Default experiment auto-created with correct S3 artifact location
- [x] Pod Ready 1/1, RESTARTS 0

### Time spent
~5 hours (mostly debugging chart incompatibilities)

### Journey: 4 incompatibilities navigated
1. **community-charts/mlflow chart 1.8.1 + MLflow 3.7**: chart values silently dropped
   non-listed env vars (MLFLOW_HOST, MLFLOW_ALLOWED_HOSTS got filtered out)
2. **MLflow 3.7 security middleware**: rejects non-localhost requests by default,
   killed K8s readiness probes
3. **--gunicorn-opts incompatible with --disable-security-middleware**: MLflow 3.7
   refused to start with both passed
4. **MLflow 3.7 init container migrated DB schema, then MLflow 2.1.1 refused
   to run against the newer schema** — needed to drop+recreate the mlflow database

### Resolution
- Switched from Helm chart to plain Kubernetes Deployment manifest
  (infra/manifests/mlflow/deployment.yaml + Terraform null_resource to apply it)
- Pinned MLflow 2.1.1 (burakince/mlflow:2.1.1 — bundles psycopg2 + boto3)
- No security middleware in 2.1.1 = no probe issues
- Manifest under direct control means future debugging is straightforward

### Tradeoffs (documented for production migration later)
- Plain manifest vs chart: simpler, easier to debug, but no chart versioning niceties
- MLflow 2.x vs 3.x: 2.x is missing some 3.x features (auth, security middleware)
  but functionally identical for our tracking + registry use case
- For production: move to MLflow 3.x with uvicorn (not gunicorn) + Istio mTLS

### Cluster RAM at end of task
~5GB across 3 nodes
