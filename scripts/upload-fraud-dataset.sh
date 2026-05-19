#!/usr/bin/env bash
# scripts/upload-fraud-dataset.sh
# Downloads the Kaggle credit card fraud dataset and uploads it to MinIO.
# Prerequisites:
#   - Kaggle CLI installed: pip install kaggle
#   - Kaggle API token: ~/.kaggle/kaggle.json
#   - MinIO port-forwarded (run: make port-forward-foundation)
#     OR mc/aws-cli installed with MinIO credentials

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/sentinelops-local.yaml}"
MINIO_USER="${MINIO_ROOT_USER:-minio}"
MINIO_PASS="${MINIO_ROOT_PASSWORD:-minio123}"
MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://localhost:9000}"
BUCKET="datasets"
DEST_KEY="fraud/creditcard.csv"
KAGGLE_DATASET="mlg-ulb/creditcardfraud"
TMPDIR=$(mktemp -d)

cleanup() { rm -rf "${TMPDIR}"; }
trap cleanup EXIT

echo -e "\n${BOLD}SentinelOps — Fraud Dataset Upload${RESET}\n"

# ── Step 1: Check Kaggle CLI ───────────────────────────────────────────────────
echo -e "${BOLD}▶ 1/4  Checking Kaggle CLI…${RESET}"
if ! command -v kaggle &>/dev/null; then
  echo -e "${RED}kaggle CLI not found. Install with:${RESET}"
  echo "  pip install kaggle"
  echo "  mkdir -p ~/.kaggle && cp /path/to/kaggle.json ~/.kaggle/ && chmod 600 ~/.kaggle/kaggle.json"
  exit 1
fi
if ! kaggle datasets list --max-size 1 &>/dev/null; then
  echo -e "${RED}Kaggle authentication failed. Ensure ~/.kaggle/kaggle.json exists with valid credentials.${RESET}"
  exit 1
fi
echo -e "  ${GREEN}✅  Kaggle CLI authenticated${RESET}"

# ── Step 2: Download dataset ───────────────────────────────────────────────────
echo -e "${BOLD}▶ 2/4  Downloading ${KAGGLE_DATASET}…${RESET}"
kaggle datasets download -d "${KAGGLE_DATASET}" -p "${TMPDIR}" --unzip
CSV_FILE="${TMPDIR}/creditcard.csv"
if [[ ! -f "${CSV_FILE}" ]]; then
  echo -e "${RED}Expected creditcard.csv not found in downloaded dataset.${RESET}"
  ls "${TMPDIR}"
  exit 1
fi
SIZE=$(du -sh "${CSV_FILE}" | awk '{print $1}')
echo -e "  ${GREEN}✅  Downloaded creditcard.csv (${SIZE})${RESET}"

# ── Step 3: Upload to MinIO ────────────────────────────────────────────────────
echo -e "${BOLD}▶ 3/4  Uploading to MinIO s3://${BUCKET}/${DEST_KEY}…${RESET}"

if command -v mc &>/dev/null && mc alias set pf-minio "${MINIO_ENDPOINT}" \
    "${MINIO_USER}" "${MINIO_PASS}" &>/dev/null; then
  mc cp "${CSV_FILE}" "pf-minio/${BUCKET}/${DEST_KEY}"
elif command -v aws &>/dev/null; then
  AWS_ACCESS_KEY_ID="${MINIO_USER}" \
  AWS_SECRET_ACCESS_KEY="${MINIO_PASS}" \
    aws --endpoint-url "${MINIO_ENDPOINT}" \
        s3 cp "${CSV_FILE}" "s3://${BUCKET}/${DEST_KEY}"
else
  echo -e "${YELLOW}No mc or aws CLI found — attempting upload via kubectl exec…${RESET}"
  POD=$(kubectl --kubeconfig="${KUBECONFIG}" get pods -n platform \
    -l app.kubernetes.io/name=minio -o jsonpath='{.items[0].metadata.name}')
  kubectl --kubeconfig="${KUBECONFIG}" cp \
    "${CSV_FILE}" "platform/${POD}:/tmp/creditcard.csv"
  kubectl --kubeconfig="${KUBECONFIG}" exec -n platform "${POD}" -- \
    sh -c "mc alias set local http://localhost:9000 ${MINIO_USER} ${MINIO_PASS} > /dev/null \
           && mc cp /tmp/creditcard.csv local/${BUCKET}/${DEST_KEY}"
fi

# ── Step 4: Verify ─────────────────────────────────────────────────────────────
echo -e "${BOLD}▶ 4/4  Verifying upload…${RESET}"
if command -v mc &>/dev/null; then
  mc ls "pf-minio/${BUCKET}/fraud/" | grep "creditcard.csv"
elif command -v aws &>/dev/null; then
  AWS_ACCESS_KEY_ID="${MINIO_USER}" \
  AWS_SECRET_ACCESS_KEY="${MINIO_PASS}" \
    aws --endpoint-url "${MINIO_ENDPOINT}" \
        s3 ls "s3://${BUCKET}/fraud/"
fi

echo ""
echo -e "${GREEN}${BOLD}✅  Dataset uploaded successfully!${RESET}"
echo -e "  S3 URI:  ${YELLOW}s3://${BUCKET}/${DEST_KEY}${RESET}"
echo -e "  MinIO:   ${YELLOW}${MINIO_ENDPOINT}/${BUCKET}/${DEST_KEY}${RESET}"
echo ""
echo "Use in MLflow/KFP pipelines with:"
echo "  endpoint_url: ${MINIO_ENDPOINT}"
echo "  bucket:       ${BUCKET}"
echo "  key:          ${DEST_KEY}"
