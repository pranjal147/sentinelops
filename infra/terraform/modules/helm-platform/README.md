# Terraform Module: helm-platform

Installs the SentinelOps foundation layer onto an existing Kubernetes cluster using Helm. Manages namespaces, cert-manager, MinIO, PostgreSQL, and Redpanda.

## What it creates

| Component | Namespace | Chart | Purpose |
|---|---|---|---|
| Namespaces | — | — | `platform`, `mlops`, `serving`, `observability`, `apps`, `chaos-mesh`, `cert-manager` |
| cert-manager | `cert-manager` | `jetstack/cert-manager` | TLS certificate management (needed Day 6 for Istio) |
| MinIO | `platform` | `oci://registry-1.docker.io/bitnamicharts/minio` | S3-compatible object store for model artifacts + datasets |
| PostgreSQL | `platform` | `oci://registry-1.docker.io/bitnamicharts/postgresql` | Metadata store for MLflow + Kubeflow Pipelines |
| Redpanda | `platform` | `redpanda/redpanda` | Kafka-compatible event bus for prediction events |

## Pre-created resources

**MinIO buckets** (created by chart `defaultBuckets`):
- `mlflow-artifacts` — MLflow model and experiment artifacts
- `kfp-artifacts` — Kubeflow Pipeline artifacts
- `datasets` — raw and processed datasets (fraud data, etc.)

**PostgreSQL databases** (created via `initdb` script):
- `mlflow` — MLflow experiment metadata
- `kfp` — Kubeflow Pipelines metadata
- `metadata` — general platform metadata

**Redpanda topics** (created via `rpk` after chart install):
- `inference-events` (3 partitions) — every prediction from transformer service
- `incidents` (3 partitions) — anomalies from detector service
- `audit` (3 partitions) — remediation agent action log
- `human-queue` (3 partitions) — escalations awaiting human approval

## Usage

```hcl
module "helm_platform" {
  source = "../../modules/helm-platform"

  kubeconfig_path     = "~/.kube/sentinelops-local.yaml"
  minio_root_user     = "minio"
  minio_root_password = "minio123"
  postgres_password   = "postgres123"
  enable_redpanda     = true
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `kubeconfig_path` | string | `~/.kube/sentinelops-local.yaml` | Path to kubeconfig for local-exec provisioners |
| `minio_root_user` | string (sensitive) | `minio` | MinIO admin username |
| `minio_root_password` | string (sensitive) | `minio123` | MinIO admin password |
| `postgres_password` | string (sensitive) | `postgres123` | PostgreSQL superuser password |
| `enable_redpanda` | bool | `true` | Install Redpanda (disable to save ~1.5GB RAM) |
| `cert_manager_chart_version` | string | `v1.16.2` | Chart version pin |
| `minio_chart_version` | string | `17.0.21` | Chart version pin |
| `postgresql_chart_version` | string | `18.6.6` | Chart version pin |
| `redpanda_chart_version` | string | `5.9.14` | Chart version pin |

## Outputs

| Name | Value | Description |
|---|---|---|
| `minio_endpoint` | `minio.platform.svc.cluster.local:9000` | S3 API in-cluster |
| `minio_console_url` | `http://localhost:9001` | After port-forward |
| `postgres_host` | `postgresql.platform.svc.cluster.local` | DB host in-cluster |
| `postgres_databases` | `[mlflow, kfp, metadata]` | Pre-created databases |
| `redpanda_brokers` | `redpanda.platform.svc.cluster.local:9092` | Broker in-cluster |
| `created_topics` | list | Topic names created |

## Accessing services

```bash
# Port-forward all services at once
bash scripts/port-forward-foundation.sh

# MinIO Console: http://localhost:9001  (admin / minio123)
# MinIO API:     http://localhost:9000
# Postgres:      localhost:5432         (postgres / postgres123)
# Redpanda Console: http://localhost:8081
```

## ⚠ Security notice

Default credentials are intentionally weak for local development.
**Never deploy these defaults to any environment accessible externally.**
Set via environment variables for CI: `TF_VAR_minio_root_password`, `TF_VAR_postgres_password`.
