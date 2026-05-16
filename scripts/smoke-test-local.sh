#!/usr/bin/env bash
# scripts/smoke-test-local.sh
# Validates that the local k3d cluster + registry work end-to-end:
#   1. Build a tiny image
#   2. Push to localhost:5000
#   3. Deploy a pod that references the in-cluster registry URL
#   4. Wait for pod Ready
#   5. Assert logs contain "hello"
#   6. Clean up
# Exits 0 on full success, 1 on any failure.

set -euo pipefail

# ── Colors ─────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

REGISTRY_HOST="localhost:5000"
REGISTRY_INTERNAL="k3d-registry.localhost:5000"
IMAGE_NAME="sentinelops-smoke"
IMAGE_TAG="v1"
POD_NAME="sentinelops-smoke"
NAMESPACE="default"
KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/sentinelops-local.yaml}"

pass() { echo -e "  ${GREEN}✅${RESET}  $1"; }
fail() { echo -e "  ${RED}❌${RESET}  $1"; }
step() { echo -e "\n${BOLD}${CYAN}▶ $1${RESET}"; }

cleanup() {
  step "Cleanup"
  kubectl --kubeconfig="${KUBECONFIG}" delete pod "${POD_NAME}" \
    --namespace="${NAMESPACE}" --ignore-not-found --wait=false 2>/dev/null || true
  docker rmi "${REGISTRY_HOST}/${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || true
  TMPDIR_CLEANUP="${_SMOKE_TMPDIR:-}"
  [[ -n "${TMPDIR_CLEANUP}" ]] && rm -rf "${TMPDIR_CLEANUP}"
  pass "Cleanup complete"
}
trap cleanup EXIT

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║       SentinelOps — Local Smoke Test                    ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"

# ── Step 1: Build tiny image ───────────────────────────────────────────────────
step "1/5  Build smoke image"
_SMOKE_TMPDIR=$(mktemp -d)
cat > "${_SMOKE_TMPDIR}/Dockerfile" <<'EOF'
FROM alpine:3.19
CMD ["sh", "-c", "echo hello && sleep 30"]
EOF
docker build --quiet -t "${REGISTRY_HOST}/${IMAGE_NAME}:${IMAGE_TAG}" "${_SMOKE_TMPDIR}"
pass "Built ${REGISTRY_HOST}/${IMAGE_NAME}:${IMAGE_TAG}"

# ── Step 2: Push to local registry ────────────────────────────────────────────
step "2/5  Push to registry (${REGISTRY_HOST})"
docker push "${REGISTRY_HOST}/${IMAGE_NAME}:${IMAGE_TAG}"
CATALOG=$(curl -sf "http://${REGISTRY_HOST}/v2/_catalog" 2>/dev/null)
echo "  Registry catalog: ${CATALOG}"
pass "Image available at ${REGISTRY_HOST}/${IMAGE_NAME}:${IMAGE_TAG}"

# ── Step 3: Deploy pod ─────────────────────────────────────────────────────────
step "3/5  Deploy pod to cluster"
# Remove any stale pod first
kubectl --kubeconfig="${KUBECONFIG}" delete pod "${POD_NAME}" \
  --namespace="${NAMESPACE}" --ignore-not-found --wait=true 2>/dev/null || true

kubectl --kubeconfig="${KUBECONFIG}" apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: sentinelops-smoke
spec:
  containers:
  - name: smoke
    image: ${REGISTRY_INTERNAL}/${IMAGE_NAME}:${IMAGE_TAG}
    imagePullPolicy: Always
  restartPolicy: Never
EOF
pass "Pod ${POD_NAME} created"

# ── Step 4: Wait for pod Ready ─────────────────────────────────────────────────
step "4/5  Wait for pod Ready (timeout 60s)"
kubectl --kubeconfig="${KUBECONFIG}" wait pod "${POD_NAME}" \
  --namespace="${NAMESPACE}" \
  --for=condition=Ready \
  --timeout=60s
pass "Pod is Ready"

# ── Step 5: Assert logs contain "hello" ───────────────────────────────────────
step "5/5  Verify pod logs"
sleep 2  # give the container's CMD a moment to execute
LOGS=$(kubectl --kubeconfig="${KUBECONFIG}" logs "${POD_NAME}" --namespace="${NAMESPACE}" 2>/dev/null)
echo "  Pod logs: ${LOGS}"
if echo "${LOGS}" | grep -q "hello"; then
  pass "Logs contain 'hello' ✓"
else
  fail "Logs do NOT contain 'hello' — got: ${LOGS}"
  exit 1
fi

echo ""
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  ✅  Smoke test PASSED — registry + cluster are healthy!  ${RESET}"
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════${RESET}"
echo ""
