#!/usr/bin/env bash
# scripts/list-postgres-dbs.sh
# Lists PostgreSQL databases via kubectl exec into the postgres pod.

set -euo pipefail

KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/sentinelops-local.yaml}"
PG_PASS="${POSTGRES_PASSWORD:-postgres123}"

POD=$(kubectl --kubeconfig="${KUBECONFIG}" get pods -n platform \
  -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [[ -z "$POD" ]]; then
  echo "PostgreSQL pod not found — is the foundation deployed? Run: make up-foundation"
  exit 1
fi

kubectl --kubeconfig="${KUBECONFIG}" exec -n platform "${POD}" -- \
  env PGPASSWORD="${PG_PASS}" psql -U postgres -c "\l"
