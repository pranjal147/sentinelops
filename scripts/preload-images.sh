#!/usr/bin/env bash
# scripts/preload-images.sh
# Load images that k3d nodes cannot pull directly (gcr.io shutdown, rate limits, etc.)
# into the cluster's containerd via docker cp + ctr import.
#
# Run this ONCE after every Docker Desktop restart before using the cluster.
# Takes ~3-5 minutes on first run (downloads), ~1 min on subsequent runs (cached).
#
# Usage:  bash scripts/preload-images.sh
#         make preload-images
set -euo pipefail

CLUSTER="${K3D_CLUSTER:-sentinelops-local}"
NODES=(
  "k3d-${CLUSTER}-server-0"
  "k3d-${CLUSTER}-agent-0"
  "k3d-${CLUSTER}-agent-1"
)

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
step() { echo -e "\n${BOLD}${CYAN}▶ $1${RESET}"; }
ok()   { echo -e "  ${GREEN}✔${RESET}  $1"; }

# Images that must be pre-loaded because they are unreachable from inside k3d nodes.
# Format: "pull_tag:load_tag"  (use same string if no retag needed)
declare -A IMAGES=(
  # argoexec: gcr.io was shut down Mar 2025; KFP hardcodes this tag in workflow pods.
  ["quay.io/argoproj/argoexec:v3.4.17"]="gcr.io/ml-pipeline/argoexec:v3.4.17-license-compliance"
  # postgresql: bitnami/postgresql purged from Docker Hub 2025; use bitnamilegacy mirror.
  ["bitnamilegacy/postgresql:16.4.0-debian-12-r10"]="bitnamilegacy/postgresql:16.4.0-debian-12-r10"
)

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

load_image() {
  local pull_tag="$1"
  local load_tag="$2"
  local tarfile="${TMPDIR}/$(echo "$load_tag" | tr '/:' '_').tar"

  step "Pulling ${pull_tag}"
  docker pull "$pull_tag"

  if [[ "$pull_tag" != "$load_tag" ]]; then
    docker tag "$pull_tag" "$load_tag"
  fi

  step "Saving ${load_tag} to tar"
  docker save "$load_tag" -o "$tarfile"
  echo "  Size: $(du -sh "$tarfile" | cut -f1)"

  for node in "${NODES[@]}"; do
    step "Loading into ${node}"
    # Remove stale partial imports first
    docker exec "$node" sh -c "
      ctr images rm '${load_tag}' 2>/dev/null || true
    " 2>/dev/null || true
    docker cp "$tarfile" "${node}:/tmp/preload.tar"
    docker exec "$node" ctr images import /tmp/preload.tar
    docker exec "$node" sh -c "rm -f /tmp/preload.tar"
    ok "$node done"
  done
}

echo -e "\n${BOLD}SentinelOps — Preloading images into k3d cluster '${CLUSTER}'${RESET}"
echo "Nodes: ${NODES[*]}"

for pull_tag in "${!IMAGES[@]}"; do
  load_tag="${IMAGES[$pull_tag]}"
  load_image "$pull_tag" "$load_tag"
done

echo -e "\n${GREEN}${BOLD}All images preloaded.${RESET}"
echo "You can now run: make kfp-apply"
