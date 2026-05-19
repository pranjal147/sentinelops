#!/usr/bin/env bash
# scripts/list-minio-buckets.sh
# Lists MinIO buckets using mc (MinIO client) via port-forward or kubectl exec.

set -euo pipefail

KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/sentinelops-local.yaml}"
MINIO_USER="${MINIO_ROOT_USER:-minio}"
MINIO_PASS="${MINIO_ROOT_PASSWORD:-minio123}"

# Try port-forward first (localhost:9000), then in-cluster exec
if curl -sf "http://localhost:9000/minio/health/ready" &>/dev/null; then
  if command -v mc &>/dev/null; then
    mc alias set local-minio "http://localhost:9000" "${MINIO_USER}" "${MINIO_PASS}" &>/dev/null
    mc ls local-minio/
  elif command -v aws &>/dev/null; then
    AWS_ACCESS_KEY_ID="${MINIO_USER}" \
    AWS_SECRET_ACCESS_KEY="${MINIO_PASS}" \
    aws --endpoint-url "http://localhost:9000" s3 ls
  else
    echo "Install mc (MinIO client) or ensure port-forward is active."
    echo "  curl -LO https://dl.min.io/client/mc/release/linux-amd64/mc"
    echo "  chmod +x mc && sudo mv mc /usr/local/bin/"
  fi
else
  # Exec into MinIO pod
  POD=$(kubectl --kubeconfig="${KUBECONFIG}" get pods -n platform \
    -l app.kubernetes.io/name=minio -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [[ -z "$POD" ]]; then
    echo "MinIO pod not found — is the foundation deployed? Run: make up-foundation"
    exit 1
  fi
  kubectl --kubeconfig="${KUBECONFIG}" exec -n platform "${POD}" -- \
    sh -c "mc alias set local http://localhost:9000 ${MINIO_USER} ${MINIO_PASS} > /dev/null && mc ls local/"
fi
