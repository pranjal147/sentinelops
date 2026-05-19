#!/usr/bin/env bash
# scripts/list-redpanda-topics.sh
# Lists Redpanda topics via kubectl exec into the redpanda-0 pod.

set -euo pipefail

KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/sentinelops-local.yaml}"

# Check pod exists and is running
if ! kubectl --kubeconfig="${KUBECONFIG}" get pod redpanda-0 -n platform &>/dev/null; then
  echo "Redpanda pod not found — is the foundation deployed? Run: make up-foundation"
  exit 1
fi

kubectl --kubeconfig="${KUBECONFIG}" exec -n platform redpanda-0 -c redpanda -- \
  rpk topic list
