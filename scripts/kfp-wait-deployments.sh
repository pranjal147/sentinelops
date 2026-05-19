#!/usr/bin/env bash
# Wait for Kubeflow Pipelines deployments after platform-agnostic apply.
# cache-deployer-deployment is a one-shot webhook installer — often never stays Available.
set -euo pipefail

KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/sentinelops-local.yaml}"
NS="kubeflow"
TIMEOUT="${KFP_WAIT_TIMEOUT:-900s}"

export KUBECONFIG

echo "Waiting for MySQL (KFP metadata) first…"
kubectl wait --for=condition=Available deployment/mysql -n "${NS}" --timeout="${TIMEOUT}"

echo "Waiting for remaining KFP deployments (excluding cache-deployer)…"
while read -r dep; do
  [[ -z "${dep}" ]] && continue
  [[ "${dep}" == "cache-deployer-deployment" ]] && continue
  echo "  … ${dep}"
  kubectl wait --for=condition=Available "deployment/${dep}" -n "${NS}" --timeout="${TIMEOUT}"
done < <(kubectl get deploy -n "${NS}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

echo "KFP deployment wait complete."
