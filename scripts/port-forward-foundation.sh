#!/usr/bin/env bash
# scripts/port-forward-foundation.sh
# Start port-forwards for all foundation services in the background.
# Usage:
#   bash scripts/port-forward-foundation.sh          # start
#   bash scripts/port-forward-foundation.sh stop     # stop all

set -euo pipefail

KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/sentinelops-local.yaml}"
PID_FILE="/tmp/sentinelops-pf.pids"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

stop_forwards() {
  if [[ -f "$PID_FILE" ]]; then
    echo -e "${YELLOW}Stopping port-forwards…${RESET}"
    while IFS= read -r pid; do
      kill "$pid" 2>/dev/null && echo "  Killed PID $pid" || true
    done < "$PID_FILE"
    rm -f "$PID_FILE"
    echo -e "${GREEN}All port-forwards stopped.${RESET}"
  else
    echo "No active port-forwards found (PID file missing)."
  fi
  exit 0
}

[[ "${1:-}" == "stop" ]] && stop_forwards

# Kill any existing forwards first
[[ -f "$PID_FILE" ]] && stop_forwards 2>/dev/null || true
> "$PID_FILE"

echo -e "\n${BOLD}Starting SentinelOps port-forwards…${RESET}\n"

start_pf() {
  local name="$1" ns="$2" svc="$3" local_port="$4" remote_port="$5"
  kubectl --kubeconfig="${KUBECONFIG}" port-forward \
    "svc/${svc}" "${local_port}:${remote_port}" -n "${ns}" &>/tmp/pf-${name}.log &
  local pid=$!
  echo "$pid" >> "$PID_FILE"
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    echo -e "  ${GREEN}✅${RESET}  ${name}: localhost:${local_port} → ${svc}:${remote_port} (PID ${pid})"
  else
    echo -e "  ${YELLOW}⚠ ${RESET}  ${name}: failed to start (check /tmp/pf-${name}.log)"
  fi
}

start_pf "minio-api"      "platform" "minio"            9000 9000

# Bitnami splits Console into its own ClusterIP Service (HTTP service port defaults to 9090)
MINIO_CONSOLE_SVC=""
MINIO_CONSOLE_SVC="$(kubectl --kubeconfig="${KUBECONFIG}" get svc -n platform --no-headers 2>/dev/null \
  | awk '{print $1}' \
  | grep -vi redpanda \
  | grep -iE '^minio.*console|^minio-console|^.*-minio-console$' \
  | head -1)"
if [[ -z "${MINIO_CONSOLE_SVC}" ]]; then
  MINIO_CONSOLE_SVC="$(kubectl --kubeconfig="${KUBECONFIG}" get svc -n platform --no-headers 2>/dev/null \
    | awk '{print $1}' \
    | grep -vi redpanda \
    | grep -i console \
    | head -1)"
fi
if [[ -n "${MINIO_CONSOLE_SVC}" ]]; then
  # Official charts.min.io chart: console Service port 9001
  # Bitnami chart: console Service port 9090 (container HTTP)
  CONSOLE_REMOTE=$(kubectl --kubeconfig="${KUBECONFIG}" get svc "${MINIO_CONSOLE_SVC}" -n platform \
    -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "9001")
  start_pf "minio-console" "platform" "${MINIO_CONSOLE_SVC}" 9001 "${CONSOLE_REMOTE}"
else
  echo -e "  ${YELLOW}⚠ ${RESET}  minio-console: no console Service yet (still deploying?)"
fi
start_pf "postgres"       "platform" "postgresql"       5432  5432
start_pf "redpanda-kafka" "platform" "redpanda"         9092  9092
start_pf "redpanda-ui"    "platform" "redpanda-console" 8081  8080

echo ""
echo -e "${BOLD}Services available at:${RESET}"
echo "  MinIO API:         http://localhost:9000  (user: minio / pass: minio123)"
echo "  MinIO Console:     http://localhost:9001"
echo "  PostgreSQL:        localhost:5432         (user: postgres / pass: postgres123)"
echo "  Redpanda Console:  http://localhost:8081"
echo ""
echo -e "  Stop with: ${YELLOW}bash scripts/port-forward-foundation.sh stop${RESET}"
echo "  PID file: $PID_FILE"
