#!/usr/bin/env bash
# scripts/install-kfp.sh
# Installs Kubeflow Pipelines 2.4.0 using the lean kustomize overlay.
# Uses platform MinIO (ExternalName) and bundled MySQL. Does NOT touch
# any platform/* resources (minio, postgresql, redpanda, mlflow).
set -euo pipefail

PIPELINE_VERSION="${PIPELINE_VERSION:-2.4.0}"
KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/sentinelops-local.yaml}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KFP_KUSTOMIZE="${REPO_ROOT}/infra/kustomize/kubeflow-pipelines"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

step() { echo -e "\n${BOLD}${CYAN}▶ $1${RESET}"; }
ok()   { echo -e "  ${GREEN}✅${RESET}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}   $1"; }
fail() { echo -e "  ${RED}❌${RESET}  $1"; exit 1; }

kubectl_cmd() { kubectl --kubeconfig="${KUBECONFIG}" "$@"; }

echo -e "\n${BOLD}SentinelOps — Kubeflow Pipelines ${PIPELINE_VERSION}${RESET}"

# ── Preconditions ─────────────────────────────────────────────────────────────
step "Checking foundation (platform MinIO must be up)"
kubectl_cmd get svc minio -n platform >/dev/null 2>&1 \
  || fail "MinIO not found in namespace platform — run: make up-foundation"

MINIO_READY=$(kubectl_cmd get pods -n platform -l app.kubernetes.io/name=minio \
  --no-headers 2>/dev/null | awk '{print $2}' | head -1)
[[ "${MINIO_READY}" == "1/1" ]] \
  || fail "MinIO pod not Ready in platform — fix foundation first"

ok "Platform MinIO is Ready"

# ── Cluster-scoped CRDs / RBAC ─────────────────────────────────────────────────
step "Applying cluster-scoped KFP resources"
kubectl_cmd apply -k \
  "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=${PIPELINE_VERSION}"

step "Waiting for KFP CRDs"
kubectl_cmd wait --for=condition=Established --timeout=120s \
  crd/workflows.argoproj.io \
  crd/workflowtemplates.argoproj.io \
  crd/scheduledworkflows.kubeflow.org \
  crd/viewers.kubeflow.org

# ── Namespaced install (no bundled MinIO) ─────────────────────────────────────
step "Applying lean KFP manifests (platform MinIO via ExternalName)"
kubectl_cmd apply -k "${KFP_KUSTOMIZE}"

# ── Staged rollout (do NOT wait on cache-deployer — it is a one-shot job) ─────
step "Waiting for core deployments (this can take 5–15 min on WSL/k3d)"
CRITICAL=(
  mysql
  workflow-controller
  ml-pipeline
  ml-pipeline-ui
  metadata-grpc-deployment
)

for dep in "${CRITICAL[@]}"; do
  echo "  … ${dep}"
  if ! kubectl_cmd wait --for=condition=Available \
      "deployment/${dep}" -n kubeflow --timeout=900s; then
    fail "${dep} did not become Available — run: kubectl describe deployment/${dep} -n kubeflow"
  fi
  ok "${dep} Available"
done

# cache-deployer runs once to install the webhook; 0/1 Ready is normal afterward
CACHE_POD=$(kubectl_cmd get pods -n kubeflow -l app=cache-deployer \
  --no-headers 2>/dev/null | awk '{print $1}' | head -1 || true)
if [[ -n "${CACHE_POD}" ]]; then
  warn "cache-deployer status (informational only):"
  kubectl_cmd get pod "${CACHE_POD}" -n kubeflow 2>/dev/null || true
fi

step "KFP UI access"
echo "  Port-forward:  kubectl port-forward svc/ml-pipeline-ui 8888:80 -n kubeflow"
echo "  Open:          http://localhost:8888"
echo ""
ok "Kubeflow Pipelines install complete"
