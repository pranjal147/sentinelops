#!/usr/bin/env bash
# scripts/verify-environment.sh
# Verifies all required CLI tools are installed for the SentinelOps project.
# Outputs ✅ or ❌ per tool. Prints install commands for missing tools.
# Exits 0 if all tools present, 1 if any are missing.

set -euo pipefail

PASS="✅"
FAIL="❌"
missing=0

check() {
  local name="$1"
  local cmd="$2"
  local install_hint="$3"

  local version
  version=$(eval "$cmd" 2>&1 | head -n1) && rc=0 || rc=1

  if [[ $rc -eq 0 && -n "$version" ]]; then
    printf "  %s  %-14s %s\n" "$PASS" "$name" "$version"
  else
    printf "  %s  %-14s NOT FOUND\n" "$FAIL" "$name"
    printf "       Install: %s\n" "$install_hint"
    missing=$((missing + 1))
  fi
}

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          SentinelOps — Environment Verification             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Container & orchestration ───────────────────────────────────────────
echo "── Container & Orchestration ──────────────────────────────────────"

check "docker" \
  "docker --version" \
  "(Windows-side) Enable Docker Desktop WSL2 integration for this distro"

check "kubectl" \
  "kubectl version --client --short 2>/dev/null || kubectl version --client" \
  'curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl'

check "helm" \
  "helm version --short" \
  "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"

check "k3d" \
  "k3d version" \
  "curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"

check "kustomize" \
  "kustomize version" \
  'curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash && sudo mv kustomize /usr/local/bin/'

echo ""
# ── Infrastructure ──────────────────────────────────────────────────────
echo "── Infrastructure ─────────────────────────────────────────────────"

check "terraform" \
  "terraform version | head -1" \
  "sudo apt-get update && sudo apt-get install -y gnupg software-properties-common && wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg && echo \"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \$(lsb_release -cs) main\" | sudo tee /etc/apt/sources.list.d/hashicorp.list && sudo apt update && sudo apt install terraform"

check "aws" \
  "aws --version" \
  'curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && unzip /tmp/awscliv2.zip -d /tmp && sudo /tmp/aws/install'

echo ""
# ── Data & utilities ────────────────────────────────────────────────────
echo "── Data & Utilities ───────────────────────────────────────────────"

check "jq" \
  "jq --version" \
  "sudo apt install -y jq"

check "yq" \
  "yq --version" \
  'sudo wget -qO /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" && sudo chmod +x /usr/local/bin/yq'

check "gh" \
  "gh --version | head -1" \
  '(type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) && sudo mkdir -p -m 755 /etc/apt/keyrings && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg && cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null && sudo apt update && sudo apt install gh -y'

echo ""
# ── Python ──────────────────────────────────────────────────────────────
echo "── Python ──────────────────────────────────────────────────────────"

PY_VERSION=$(python3 --version 2>&1 | awk '{print $2}') && PY_RC=0 || PY_RC=1
if [[ $PY_RC -eq 0 ]]; then
  MAJOR=$(echo "$PY_VERSION" | cut -d. -f1)
  MINOR=$(echo "$PY_VERSION" | cut -d. -f2)
  if [[ "$MAJOR" -ge 3 && "$MINOR" -ge 11 ]]; then
    printf "  %s  %-14s Python %s\n" "$PASS" "python3" "$PY_VERSION"
  else
    printf "  %s  %-14s Python %s (need 3.11+)\n" "$FAIL" "python3" "$PY_VERSION"
    printf "       Install: %s\n" "sudo apt install -y python3.11 python3.11-venv python3-pip"
    missing=$((missing + 1))
  fi
else
  printf "  %s  %-14s NOT FOUND\n" "$FAIL" "python3"
  printf "       Install: %s\n" "sudo apt install -y python3.11 python3.11-venv python3-pip"
  missing=$((missing + 1))
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════"
if [[ $missing -eq 0 ]]; then
  echo "  ${PASS}  All tools verified — environment is ready for Day 1!"
  echo "═══════════════════════════════════════════════════════════════════"
  exit 0
else
  echo "  ${FAIL}  ${missing} tool(s) missing — install them before proceeding."
  echo "  Run the install commands above, then re-run this script."
  echo "═══════════════════════════════════════════════════════════════════"
  exit 1
fi
