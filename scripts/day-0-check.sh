#!/usr/bin/env bash
# scripts/day-0-check.sh
# Day 0 verification — exits 0 if all checks pass, 1 otherwise.
# Usage: bash scripts/day-0-check.sh [--full]
#   --full  also runs k3d smoke test (slow, ~60s)

set -uo pipefail

# ── Colors ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

FULL_MODE=false
[[ "${1:-}" == "--full" ]] && FULL_MODE=true

pass_count=0
fail_count=0
declare -a results=()

record() {
  local status="$1"   # PASS | FAIL | SKIP
  local label="$2"
  local detail="$3"
  results+=("$status|$label|$detail")
  if [[ "$status" == "PASS" ]]; then
    pass_count=$((pass_count + 1))
    printf "  ${GREEN}✅${RESET}  %-42s ${GREEN}%s${RESET}\n" "$label" "$detail"
  elif [[ "$status" == "FAIL" ]]; then
    fail_count=$((fail_count + 1))
    printf "  ${RED}❌${RESET}  %-42s ${RED}%s${RESET}\n" "$label" "$detail"
  else
    printf "  ${YELLOW}⏭ ${RESET}  %-42s ${YELLOW}%s${RESET}\n" "$label" "$detail"
  fi
}

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║        SentinelOps — Day 0 Verification                 ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""

# ── Check 1: WSL2 detected ─────────────────────────────────────────────────────
echo -e "${BOLD}── System ─────────────────────────────────────────────────────${RESET}"
KERNEL=$(uname -r 2>/dev/null || echo "unknown")
if echo "$KERNEL" | grep -qiE "microsoft|WSL"; then
  record "PASS" "WSL2 detected" "$KERNEL"
else
  record "FAIL" "WSL2 detected" "kernel=$KERNEL (expected WSL2)"
fi

# ── Check 2: Working directory under ~/sentinelops ─────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if echo "$REPO_ROOT" | grep -q "^/home/"; then
  record "PASS" "Repo on Linux filesystem" "$REPO_ROOT"
elif echo "$REPO_ROOT" | grep -q "^/mnt/c/"; then
  record "FAIL" "Repo on Linux filesystem" "Currently at $REPO_ROOT — move to ~/sentinelops"
else
  record "PASS" "Repo accessible" "$REPO_ROOT"
fi

echo ""
# ── Check 3: Docker daemon reachable ──────────────────────────────────────────
echo -e "${BOLD}── Container & Orchestration ──────────────────────────────────${RESET}"
if docker ps &>/dev/null; then
  DOCKER_VER=$(docker --version 2>&1 | head -1)
  record "PASS" "Docker daemon reachable" "$DOCKER_VER"
else
  record "FAIL" "Docker daemon reachable" "docker ps failed — enable WSL2 integration in Docker Desktop"
fi

# ── Check 4: CLI tools on PATH ─────────────────────────────────────────────────
check_tool() {
  local name="$1"
  local vcmd="$2"
  local ver
  ver=$(eval "$vcmd" 2>&1 | head -1) && rc=0 || rc=1
  if [[ $rc -eq 0 && -n "$ver" ]]; then
    record "PASS" "$name on PATH" "$ver"
  else
    record "FAIL" "$name on PATH" "not found"
  fi
}

check_tool "kubectl"   "kubectl version --client --short 2>/dev/null || kubectl version --client 2>&1 | head -1"
check_tool "helm"      "helm version --short"
check_tool "k3d"       "k3d version | head -1"
check_tool "terraform" "terraform version | head -1"
check_tool "aws CLI"   "aws --version"
check_tool "gh"        "gh --version | head -1"
check_tool "jq"        "jq --version"
check_tool "yq"        "yq --version | head -1"

# Python 3.11+ check
PY_VER=$(python3 --version 2>&1 | awk '{print $2}') && PY_RC=0 || PY_RC=1
if [[ $PY_RC -eq 0 ]]; then
  PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
  PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
  if [[ "$PY_MAJOR" -ge 3 && "$PY_MINOR" -ge 11 ]]; then
    record "PASS" "python3 ≥ 3.11" "Python $PY_VER"
  else
    record "FAIL" "python3 ≥ 3.11" "Python $PY_VER (need 3.11+)"
  fi
else
  record "FAIL" "python3 ≥ 3.11" "python3 not found"
fi

echo ""
# ── Check 5: AWS configured ────────────────────────────────────────────────────
echo -e "${BOLD}── Cloud & API Credentials ─────────────────────────────────────${RESET}"
if AWS_OUT=$(aws sts get-caller-identity 2>&1); then
  ACCOUNT=$(echo "$AWS_OUT" | jq -r '.Account' 2>/dev/null || echo "unknown")
  record "PASS" "AWS credentials valid" "Account: $ACCOUNT"
else
  record "FAIL" "AWS credentials valid" "aws sts get-caller-identity failed"
fi

# ── Check 6: Anthropic API key set ────────────────────────────────────────────
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  KEY_PREVIEW="${ANTHROPIC_API_KEY:0:7}…"
  record "PASS" "ANTHROPIC_API_KEY set" "$KEY_PREVIEW"
else
  record "FAIL" "ANTHROPIC_API_KEY set" "env var is empty — add to ~/.bashrc"
fi

# ── Check 7: Anthropic API reachable ──────────────────────────────────────────
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 10 \
    -H "x-api-key: ${ANTHROPIC_API_KEY}" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d '{"model":"claude-3-haiku-20240307","max_tokens":16,"messages":[{"role":"user","content":"ping"}]}' \
    "https://api.anthropic.com/v1/messages" 2>/dev/null)
  if [[ "$HTTP_STATUS" == "200" ]]; then
    record "PASS" "Anthropic API reachable" "HTTP $HTTP_STATUS"
  else
    record "FAIL" "Anthropic API reachable" "HTTP $HTTP_STATUS (check key + network)"
  fi
else
  record "SKIP" "Anthropic API reachable" "skipped — ANTHROPIC_API_KEY not set"
fi

# ── Check 8: GitHub CLI authenticated ─────────────────────────────────────────
if gh auth status &>/dev/null; then
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "authenticated")
  record "PASS" "GitHub CLI authenticated" "user: $GH_USER"
else
  record "FAIL" "GitHub CLI authenticated" "run: gh auth login"
fi

echo ""
# ── Check 9: k3d smoke test (--full only) ─────────────────────────────────────
echo -e "${BOLD}── Smoke Test ──────────────────────────────────────────────────${RESET}"
if $FULL_MODE; then
  SMOKE_CLUSTER="sentinelops-smoke-$$"
  echo -e "  ${YELLOW}⏳  Running k3d smoke test (this takes ~30s)…${RESET}"
  if k3d cluster create "$SMOKE_CLUSTER" --wait --timeout 60s &>/dev/null 2>&1; then
    NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    k3d cluster delete "$SMOKE_CLUSTER" &>/dev/null 2>&1 || true
    record "PASS" "k3d smoke test" "$NODE_COUNT node(s) created and deleted"
  else
    k3d cluster delete "$SMOKE_CLUSTER" &>/dev/null 2>&1 || true
    record "FAIL" "k3d smoke test" "cluster create failed"
  fi
else
  record "SKIP" "k3d smoke test" "pass --full to run"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
total=$((pass_count + fail_count))
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
if [[ $fail_count -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}✅  All ${pass_count} checks passed — Day 0 complete!${RESET}"
else
  echo -e "  ${RED}${BOLD}❌  ${fail_count}/${total} check(s) failed${RESET}"
  echo ""
  echo -e "  ${YELLOW}Failed checks:${RESET}"
  for r in "${results[@]}"; do
    IFS='|' read -r status label detail <<< "$r"
    if [[ "$status" == "FAIL" ]]; then
      echo -e "    ${RED}•${RESET} $label — $detail"
    fi
  done
fi
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
echo ""

[[ $fail_count -eq 0 ]] && exit 0 || exit 1
