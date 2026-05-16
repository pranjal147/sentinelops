#!/usr/bin/env bash
# scripts/day-1-check.sh
# Day 1 verification — checks all success criteria for the local k3d cluster.
# Usage: bash scripts/day-1-check.sh [--smoke] [--cycle]
#   --smoke   run make smoke-test-local (deploys a pod, ~30s)
#   --cycle   run a full destroy+apply cycle and time it (~3 min)

set -uo pipefail

# ── Colors ─────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

RUN_SMOKE=false
RUN_CYCLE=false
for arg in "$@"; do
  [[ "$arg" == "--smoke" ]] && RUN_SMOKE=true
  [[ "$arg" == "--cycle" ]] && RUN_CYCLE=true
done

pass_count=0
fail_count=0
declare -a results=()

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_LOCAL="${REPO_ROOT}/infra/terraform/envs/local"
KUBECONFIG_LOCAL="${HOME}/.kube/sentinelops-local.yaml"

record() {
  local status="$1" label="$2" detail="$3"
  results+=("$status|$label|$detail")
  if [[ "$status" == "PASS" ]]; then
    pass_count=$((pass_count + 1))
    printf "  ${GREEN}✅${RESET}  %-48s ${GREEN}%s${RESET}\n" "$label" "$detail"
  elif [[ "$status" == "FAIL" ]]; then
    fail_count=$((fail_count + 1))
    printf "  ${RED}❌${RESET}  %-48s ${RED}%s${RESET}\n" "$label" "$detail"
  else
    printf "  ${YELLOW}⏭ ${RESET}  %-48s ${YELLOW}%s${RESET}\n" "$label" "$detail"
  fi
}

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║        SentinelOps — Day 1 Verification                 ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""

# ── Check 1: Module files exist ────────────────────────────────────────────────
echo -e "${BOLD}── Terraform module files ─────────────────────────────────────${RESET}"
MODULE="${REPO_ROOT}/infra/terraform/modules/local-cluster"
for f in main.tf variables.tf outputs.tf versions.tf README.md; do
  if [[ -f "${MODULE}/${f}" ]]; then
    record "PASS" "modules/local-cluster/${f} exists" "$(wc -l < "${MODULE}/${f}") lines"
  else
    record "FAIL" "modules/local-cluster/${f} exists" "FILE NOT FOUND"
  fi
done

echo ""
# ── Check 2: Environment files exist ──────────────────────────────────────────
echo -e "${BOLD}── Terraform environment files ────────────────────────────────${RESET}"
for f in main.tf versions.tf backend.tf README.md; do
  if [[ -f "${TF_LOCAL}/${f}" ]]; then
    record "PASS" "envs/local/${f} exists" "$(wc -l < "${TF_LOCAL}/${f}") lines"
  else
    record "FAIL" "envs/local/${f} exists" "FILE NOT FOUND"
  fi
done

echo ""
# ── Check 3: terraform fmt ────────────────────────────────────────────────────
echo -e "${BOLD}── Code quality ───────────────────────────────────────────────${RESET}"
if terraform fmt -check -recursive "${REPO_ROOT}/infra/terraform/" &>/dev/null; then
  record "PASS" "terraform fmt -check passes" "all .tf files formatted"
else
  BAD=$(terraform fmt -check -recursive "${REPO_ROOT}/infra/terraform/" 2>&1 | head -5)
  record "FAIL" "terraform fmt -check passes" "run: make fmt-tf | ${BAD}"
fi

# ── Check 4: terraform validate ───────────────────────────────────────────────
cd "${TF_LOCAL}"
if terraform init -backend=false -input=false &>/dev/null \
   && terraform validate &>/dev/null; then
  record "PASS" "terraform validate passes" "envs/local"
else
  VALIDATE_ERR=$(terraform validate 2>&1 | tail -3)
  record "FAIL" "terraform validate passes" "${VALIDATE_ERR}"
fi
cd "${REPO_ROOT}"

echo ""
# ── Check 5: Cluster nodes ────────────────────────────────────────────────────
echo -e "${BOLD}── Live cluster ───────────────────────────────────────────────${RESET}"
if [[ -f "${KUBECONFIG_LOCAL}" ]]; then
  READY_NODES=$(kubectl --kubeconfig="${KUBECONFIG_LOCAL}" get nodes \
    --no-headers 2>/dev/null | grep -c " Ready" || echo "0")
  if [[ "${READY_NODES}" -eq 3 ]]; then
    record "PASS" "Cluster has 3 Ready nodes" "${READY_NODES}/3 Ready"
  elif [[ "${READY_NODES}" -gt 0 ]]; then
    record "FAIL" "Cluster has 3 Ready nodes" "${READY_NODES}/3 Ready (run make up-local first?)"
  else
    record "FAIL" "Cluster has 3 Ready nodes" "0 nodes — run make up-local first"
  fi
else
  record "FAIL" "Cluster has 3 Ready nodes" "kubeconfig not found at ${KUBECONFIG_LOCAL}"
fi

# ── Check 6: Registry accessible ──────────────────────────────────────────────
if curl -sf "http://localhost:5000/v2/_catalog" &>/dev/null; then
  CATALOG=$(curl -sf "http://localhost:5000/v2/_catalog" 2>/dev/null)
  record "PASS" "Registry accessible (localhost:5000)" "${CATALOG}"
else
  record "FAIL" "Registry accessible (localhost:5000)" "curl http://localhost:5000/v2/_catalog failed"
fi

# ── Check 7: terraform plan shows no changes ──────────────────────────────────
cd "${TF_LOCAL}"
if terraform init -backend=false -input=false &>/dev/null; then
  PLAN_OUT=$(terraform plan -detailed-exitcode 2>&1)
  PLAN_RC=$?
  if [[ $PLAN_RC -eq 0 ]]; then
    record "PASS" "terraform plan — no changes" "state matches desired"
  elif [[ $PLAN_RC -eq 2 ]]; then
    record "FAIL" "terraform plan — no changes" "plan has changes (drift detected)"
  else
    record "FAIL" "terraform plan — no changes" "plan failed — run make up-local first"
  fi
fi
cd "${REPO_ROOT}"

echo ""
# ── Check 8: Smoke test ────────────────────────────────────────────────────────
echo -e "${BOLD}── Smoke test ─────────────────────────────────────────────────${RESET}"
if $RUN_SMOKE; then
  echo -e "  ${YELLOW}⏳  Running smoke test (~30s)…${RESET}"
  if KUBECONFIG="${KUBECONFIG_LOCAL}" bash "${REPO_ROOT}/scripts/smoke-test-local.sh" &>/dev/null; then
    record "PASS" "Smoke test (registry + pod)" "image pushed, pod ran, logs OK"
  else
    record "FAIL" "Smoke test (registry + pod)" "run manually: make smoke-test-local"
  fi
else
  record "SKIP" "Smoke test (registry + pod)" "pass --smoke to run"
fi

# ── Check 9: Destroy + apply cycle ────────────────────────────────────────────
if $RUN_CYCLE; then
  echo -e "  ${YELLOW}⏳  Running destroy+apply cycle (~3 min)…${RESET}"
  START_TS=$(date +%s)
  cd "${TF_LOCAL}"
  if terraform destroy -auto-approve &>/dev/null \
     && terraform apply -auto-approve &>/dev/null; then
    END_TS=$(date +%s)
    ELAPSED=$(( END_TS - START_TS ))
    if [[ $ELAPSED -lt 180 ]]; then
      record "PASS" "Destroy+apply cycle < 3 min" "${ELAPSED}s"
    else
      record "FAIL" "Destroy+apply cycle < 3 min" "${ELAPSED}s (too slow)"
    fi
  else
    record "FAIL" "Destroy+apply cycle completes" "cycle failed"
  fi
  cd "${REPO_ROOT}"
else
  record "SKIP" "Destroy+apply cycle < 3 min" "pass --cycle to run"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
total=$((pass_count + fail_count))
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
if [[ $fail_count -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}✅  All ${pass_count} checks passed — Day 1 complete!${RESET}"
else
  echo -e "  ${RED}${BOLD}❌  ${fail_count}/${total} check(s) failed${RESET}"
  echo ""
  echo -e "  ${YELLOW}Failed:${RESET}"
  for r in "${results[@]}"; do
    IFS='|' read -r status label detail <<< "$r"
    [[ "$status" == "FAIL" ]] && echo -e "    ${RED}•${RESET} ${label} — ${detail}"
  done
fi
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
echo ""

[[ $fail_count -eq 0 ]] && exit 0 || exit 1
