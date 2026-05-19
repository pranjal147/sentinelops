#!/usr/bin/env bash
# scripts/cleanup-kfp.sh — remove KFP from the cluster (keeps foundation + MLflow).
#
# SAFETY — only deletes namespace kubeflow and KFP cluster-scoped RBAC/CRDs.
# Does NOT touch: platform (minio/postgresql/redpanda), mlops (mlflow), cert-manager.
set -euo pipefail

KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/sentinelops-local.yaml}"
PIPELINE_VERSION="${PIPELINE_VERSION:-2.3.0}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kubectl --kubeconfig="${KUBECONFIG}" delete -k "${REPO_ROOT}/infra/kustomize/kubeflow-pipelines" --ignore-not-found --wait=false
kubectl --kubeconfig="${KUBECONFIG}" delete -k \
  "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=${PIPELINE_VERSION}" \
  --ignore-not-found --wait=false

echo "Waiting for kubeflow namespace to terminate…"
kubectl --kubeconfig="${KUBECONFIG}" delete namespace kubeflow --ignore-not-found --wait=true --timeout=300s \
  || echo "Namespace still terminating — check: kubectl get ns kubeflow"

echo "Done. Foundation (platform/*) and mlops/mlflow were not removed."
