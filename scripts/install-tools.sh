#!/usr/bin/env bash
# scripts/install-tools.sh
# Installs all missing SentinelOps CLI tools in one shot.
# Run inside WSL2 Ubuntu. Idempotent — safe to re-run.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

step() { echo -e "\n${BOLD}${CYAN}▶ $1${RESET}"; }
done_() { echo -e "${GREEN}✅ $1${RESET}"; }

# ── Docker (Windows-side only) ─────────────────────────────────────────────────
step "Docker"
if docker --version &>/dev/null; then
  done_ "Docker already reachable — $(docker --version)"
else
  echo -e "${YELLOW}⚠  Docker not found in WSL2."
  echo "   Action required on Windows side:"
  echo "   1. Open Docker Desktop → Settings → Resources → WSL Integration"
  echo "   2. Enable integration for 'Ubuntu' (your distro)"
  echo "   3. Click 'Apply & Restart'"
  echo -e "   4. Re-open this Ubuntu terminal and re-run this script.${RESET}"
fi

# ── kubectl ────────────────────────────────────────────────────────────────────
step "kubectl"
if kubectl version --client &>/dev/null; then
  done_ "kubectl already installed"
else
  KUBECTL_VER=$(curl -sL https://dl.k8s.io/release/stable.txt)
  curl -sLO "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
  done_ "kubectl ${KUBECTL_VER} installed"
fi

# ── Helm ───────────────────────────────────────────────────────────────────────
step "Helm"
if helm version &>/dev/null; then
  done_ "Helm already installed"
else
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  done_ "Helm installed"
fi

# ── k3d ───────────────────────────────────────────────────────────────────────
step "k3d"
if k3d version &>/dev/null; then
  done_ "k3d already installed"
else
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  done_ "k3d installed"
fi

# ── kustomize ─────────────────────────────────────────────────────────────────
step "kustomize"
if kustomize version &>/dev/null; then
  done_ "kustomize already installed"
else
  curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
  sudo mv kustomize /usr/local/bin/kustomize
  done_ "kustomize installed"
fi

# ── Terraform ─────────────────────────────────────────────────────────────────
step "Terraform"
if terraform version &>/dev/null; then
  done_ "Terraform already installed"
else
  sudo apt-get install -y gnupg software-properties-common lsb-release
  wget -O- https://apt.releases.hashicorp.com/gpg \
    | gpg --dearmor \
    | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update -qq
  sudo apt-get install -y terraform
  done_ "Terraform installed"
fi

# ── AWS CLI v2 ────────────────────────────────────────────────────────────────
step "AWS CLI v2"
if aws --version &>/dev/null; then
  done_ "AWS CLI already installed"
else
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp/awscli
  sudo /tmp/awscli/aws/install
  rm -rf /tmp/awscliv2.zip /tmp/awscli
  done_ "AWS CLI v2 installed"
fi

# ── yq ────────────────────────────────────────────────────────────────────────
step "yq"
if yq --version &>/dev/null; then
  done_ "yq already installed"
else
  sudo wget -qO /usr/local/bin/yq \
    "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
  sudo chmod +x /usr/local/bin/yq
  done_ "yq installed"
fi

# ── GitHub CLI ────────────────────────────────────────────────────────────────
step "GitHub CLI (gh)"
if gh --version &>/dev/null; then
  done_ "gh already installed"
else
  sudo mkdir -p /etc/apt/keyrings
  wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] \
https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt-get update -qq
  sudo apt-get install -y gh
  done_ "GitHub CLI installed"
fi

# ── Final summary ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}All installs complete. Re-running verify-environment.sh…${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
bash "$(dirname "$0")/verify-environment.sh"
