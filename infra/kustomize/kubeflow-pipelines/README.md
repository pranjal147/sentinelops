# DEPRECATED — use Terraform KFP install instead

**Current approach (Day 3 handoff):** `make kfp-apply` installs upstream **`platform-agnostic`** via `null_resource` in `infra/terraform/modules/helm-platform/main.tf` (bundled MySQL + MinIO inside `kubeflow`). See `docs/CLAUDE_CODE_HANDOFF.md`.

This lean overlay is kept for reference only. Do not use `scripts/install-kfp.sh` against a working foundation cluster.

---

# Kubeflow Pipelines (lean local overlay) — historical notes

Upstream `platform-agnostic` installs **its own MinIO + MySQL** on top of SentinelOps foundation MinIO/Postgres. On a 3-node k3d dev cluster that usually causes:

- **RAM pressure** (~2.8GB already used before KFP)
- **Duplicate object storage** (platform `minio` + kubeflow `minio`)
- **False-negative health checks** (`kubectl wait deployment --all` waits on `cache-deployer-deployment`, which is a one-shot job and often never stays `Available`)

This overlay:

| Component | Source |
|-----------|--------|
| Pipeline API, UI, Argo, metadata | Upstream KFP 2.3.0 generic + metadata |
| MySQL | Bundled (KFP metadata requires MySQL, not the Postgres `kfp` DB) |
| Object storage | **Platform MinIO** via `ExternalName` service `minio-service` → `minio.platform.svc.cluster.local` |
| Artifact bucket | `kfp-artifacts` (Day 2 bucket) |

## Install

**Prerequisite:** `platform/minio`, `platform/postgresql`, and `platform/redpanda` must already be Running. Do **not** run `make up-foundation` or `terraform apply` on a healthy cluster unless you intend to upgrade Helm charts (can restart pods).

```bash
export KUBECONFIG=~/.kube/sentinelops-local.yaml
bash scripts/install-kfp.sh
```

## Remove (keeps foundation + MLflow)

```bash
bash scripts/cleanup-kfp.sh
```

## UI

```bash
kubectl port-forward svc/ml-pipeline-ui 8888:80 -n kubeflow
# http://localhost:8888
```
