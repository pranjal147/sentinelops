#!/usr/bin/env bash
# scripts/day-2-check.sh
# Day 2 verification — foundation layer (MinIO, Postgres, Redpanda, cert-manager).
# Usage: bash scripts/day-2-check.sh

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/sentinelops-local.yaml}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_LOCAL="${REPO_ROOT}/infra/terraform/envs/local"
MODULE="${REPO_ROOT}/infra/terraform/modules/helm-platform"

pass_count=0
fail_count=0
declare -a results=()

record() {
  local status="$1" label="$2" detail="$3"
  results+=("$status|$label|$detail")
  if [[ "$status" == "PASS" ]]; then
    pass_count=$((pass_count + 1))
    printf "  ${GREEN}✅${RESET}  %-52s ${GREEN}%s${RESET}\n" "$label" "$detail"
  elif [[ "$status" == "FAIL" ]]; then
    fail_count=$((fail_count + 1))
    printf "  ${RED}❌${RESET}  %-52s ${RED}%s${RESET}\n" "$label" "$detail"
  else
    printf "  ${YELLOW}⏭ ${RESET}  %-52s ${YELLOW}%s${RESET}\n" "$label" "$detail"
  fi
}

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║        SentinelOps — Day 2 Verification                 ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""

# ── Check 1: Terraform files ───────────────────────────────────────────────────
echo -e "${BOLD}── Terraform files ────────────────────────────────────────────${RESET}"
for f in main.tf variables.tf outputs.tf versions.tf README.md; do
  [[ -f "${MODULE}/${f}" ]] \
    && record "PASS" "helm-platform/${f} exists" "$(wc -l < "${MODULE}/${f}") lines" \
    || record "FAIL" "helm-platform/${f} exists" "FILE NOT FOUND"
done
for f in minio.yaml postgresql.yaml redpanda.yaml cert-manager.yaml; do
  [[ -f "${REPO_ROOT}/infra/helm-values/${f}" ]] \
    && record "PASS" "helm-values/${f} exists" "" \
    || record "FAIL" "helm-values/${f} exists" "FILE NOT FOUND"
done

echo ""
# ── Check 2: Code quality ──────────────────────────────────────────────────────
echo -e "${BOLD}── Code quality ───────────────────────────────────────────────${RESET}"
if terraform fmt -check -recursive "${REPO_ROOT}/infra/terraform/" &>/dev/null; then
  record "PASS" "terraform fmt -check passes" ""
else
  record "FAIL" "terraform fmt -check passes" "run: make fmt-tf"
fi

cd "${TF_LOCAL}"
if terraform init -upgrade -input=false &>/dev/null && terraform validate &>/dev/null; then
  record "PASS" "terraform validate passes" "envs/local"
else
  ERR=$(terraform validate 2>&1 | tail -2)
  record "FAIL" "terraform validate passes" "${ERR}"
fi
cd "${REPO_ROOT}"

echo ""
# ── Check 3: Namespaces ────────────────────────────────────────────────────────
echo -e "${BOLD}── Kubernetes namespaces ──────────────────────────────────────${RESET}"
for ns in cert-manager platform mlops serving observability apps chaos-mesh; do
  if kubectl --kubeconfig="${KUBECONFIG}" get namespace "${ns}" \
      -o jsonpath='{.metadata.labels.project}' 2>/dev/null | grep -q "sentinelops"; then
    record "PASS" "Namespace ${ns} exists (labelled)" ""
  elif kubectl --kubeconfig="${KUBECONFIG}" get namespace "${ns}" &>/dev/null; then
    record "FAIL" "Namespace ${ns} exists (labelled)" "exists but missing project=sentinelops label"
  else
    record "FAIL" "Namespace ${ns} exists (labelled)" "NOT FOUND — run: make up-foundation"
  fi
done

echo ""
# ── Check 4: Helm releases ─────────────────────────────────────────────────────
echo -e "${BOLD}── Helm releases ──────────────────────────────────────────────${RESET}"
for release_ns in "cert-manager:cert-manager" "minio:platform" "postgresql:platform" "redpanda:platform"; do
  release="${release_ns%%:*}"
  ns="${release_ns##*:}"
  status=$(helm --kubeconfig="${KUBECONFIG}" status "${release}" -n "${ns}" \
    -o json 2>/dev/null | jq -r '.info.status' 2>/dev/null || echo "")
  if [[ "$status" == "deployed" ]]; then
    record "PASS" "Helm release ${release} (${ns})" "STATUS=deployed"
  else
    record "FAIL" "Helm release ${release} (${ns})" "status=${status:-not found}"
  fi
done

echo ""
# ── Check 5: Pod readiness ─────────────────────────────────────────────────────
echo -e "${BOLD}── Pod readiness ──────────────────────────────────────────────${RESET}"
check_pods() {
  local ns="$1" label="$2" display="$3"
  READY=$(kubectl --kubeconfig="${KUBECONFIG}" get pods -n "${ns}" \
    -l "${label}" --no-headers 2>/dev/null | grep -c " Running" || echo "0")
  if [[ "${READY}" -gt 0 ]]; then
    record "PASS" "${display} pods Running" "${READY} pod(s)"
  else
    record "FAIL" "${display} pods Running" "0 Running in namespace ${ns}"
  fi
}
check_pods "cert-manager" "app.kubernetes.io/instance=cert-manager" "cert-manager"
check_pods "platform"     "app.kubernetes.io/name=minio"            "MinIO"
check_pods "platform"     "app.kubernetes.io/name=postgresql"       "PostgreSQL"
check_pods "platform"     "app.kubernetes.io/name=redpanda"         "Redpanda"

echo ""
# ── Check 6: MinIO buckets ────────────────────────────────────────────────────
echo -e "${BOLD}── MinIO buckets ──────────────────────────────────────────────${RESET}"
if curl -sf "http://localhost:9000/minio/health/ready" &>/dev/null; then
  for bucket in mlflow-artifacts kfp-artifacts datasets; do
    if AWS_ACCESS_KEY_ID=minio AWS_SECRET_ACCESS_KEY=minio123 \
        aws --endpoint-url http://localhost:9000 s3 ls "s3://${bucket}" &>/dev/null; then
      record "PASS" "MinIO bucket ${bucket}" "accessible"
    else
      record "FAIL" "MinIO bucket ${bucket}" "not found (port-forward active?)"
    fi
  done
else
  record "SKIP" "MinIO buckets" "port-forward not active — run: make port-forward-foundation"
fi

echo ""
# ── Check 7: PostgreSQL databases ─────────────────────────────────────────────
echo -e "${BOLD}── PostgreSQL databases ───────────────────────────────────────${RESET}"
PG_POD=$(kubectl --kubeconfig="${KUBECONFIG}" get pods -n platform \
  -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "${PG_POD}" ]]; then
  for db in mlflow kfp metadata; do
    EXISTS=$(kubectl --kubeconfig="${KUBECONFIG}" exec -n platform "${PG_POD}" -- \
      env PGPASSWORD=postgres123 psql -U postgres -tAc \
      "SELECT 1 FROM pg_database WHERE datname='${db}'" 2>/dev/null | tr -d ' ')
    [[ "$EXISTS" == "1" ]] \
      && record "PASS" "PostgreSQL database ${db}" "exists" \
      || record "FAIL" "PostgreSQL database ${db}" "not found"
  done
else
  record "FAIL" "PostgreSQL databases" "PG pod not found — run: make up-foundation"
fi

echo ""
# ── Check 8: Redpanda topics ──────────────────────────────────────────────────
echo -e "${BOLD}── Redpanda topics ────────────────────────────────────────────${RESET}"
if kubectl --kubeconfig="${KUBECONFIG}" get pod redpanda-0 -n platform &>/dev/null; then
  TOPIC_LIST=$(kubectl --kubeconfig="${KUBECONFIG}" exec -n platform redpanda-0 \
    -c redpanda -- rpk topic list 2>/dev/null || echo "")
  for topic in inference-events incidents audit human-queue; do
    echo "$TOPIC_LIST" | grep -q "^${topic}" \
      && record "PASS" "Redpanda topic ${topic}" "exists" \
      || record "FAIL" "Redpanda topic ${topic}" "not found"
  done
else
  record "FAIL" "Redpanda topics" "redpanda-0 pod not found — run: make up-foundation"
fi

echo ""
# ── Check 9: Memory usage ─────────────────────────────────────────────────────
echo -e "${BOLD}── Resource usage ─────────────────────────────────────────────${RESET}"
if kubectl --kubeconfig="${KUBECONFIG}" top nodes &>/dev/null 2>&1; then
  MEM_LINE=$(kubectl --kubeconfig="${KUBECONFIG}" top nodes --no-headers 2>/dev/null | head -1)
  record "PASS" "kubectl top nodes (metrics-server)" "${MEM_LINE}"
else
  record "SKIP" "Memory usage check" "metrics-server not ready or not available"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
total=$((pass_count + fail_count))
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
if [[ $fail_count -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}✅  All ${pass_count} checks passed — Day 2 complete!${RESET}"
else
  echo -e "  ${RED}${BOLD}❌  ${fail_count}/${total} check(s) failed${RESET}"
  echo ""
  for r in "${results[@]}"; do
    IFS='|' read -r status label detail <<< "$r"
    [[ "$status" == "FAIL" ]] && echo -e "    ${RED}•${RESET} ${label} — ${detail}"
  done
fi
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
echo ""

[[ $fail_count -eq 0 ]] && exit 0 || exit 1
