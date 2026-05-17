locals {
  kubeconfig = pathexpand(var.kubeconfig_path)

  # Values files live at infra/helm-values/ — 3 levels up from this module directory
  values_dir = "${path.module}/../../../helm-values"

  redpanda_topics = ["inference-events", "incidents", "audit", "human-queue"]
}

# ── Namespaces ─────────────────────────────────────────────────────────────────

resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "project"                      = "sentinelops"
    }
  }
}

resource "kubernetes_namespace" "platform_namespaces" {
  for_each = toset(["platform", "mlops", "serving", "observability", "apps", "chaos-mesh"])

  metadata {
    name = each.key
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "project"                      = "sentinelops"
    }
  }
}

# ── cert-manager ───────────────────────────────────────────────────────────────
# Required by Istio/KServe (Day 6). Install early so CRDs are stable by then.

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_chart_version
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name

  values = [file("${local.values_dir}/cert-manager.yaml")]

  set {
    name  = "installCRDs"
    value = "true"
  }

  wait          = true
  wait_for_jobs = true
  timeout       = 300

  depends_on = [kubernetes_namespace.cert_manager]
}

# ── MinIO ──────────────────────────────────────────────────────────────────────
# S3-compatible object store for model artifacts, datasets, and pipeline outputs.
# ⚠ DEV ONLY: credentials are intentionally simple — change before any exposure.

resource "helm_release" "minio" {
  name       = "minio"
  repository = "https://charts.min.io/"
  chart      = "minio"
  version    = var.minio_chart_version
  namespace  = kubernetes_namespace.platform_namespaces["platform"].metadata[0].name

  values = [file("${local.values_dir}/minio.yaml")]

  set {
    name  = "rootUser"
    value = var.minio_root_user
  }

  set_sensitive {
    name  = "rootPassword"
    value = var.minio_root_password
  }

  wait    = true
  timeout = 600
  atomic  = true

  depends_on = [kubernetes_namespace.platform_namespaces]
}

# ── PostgreSQL ─────────────────────────────────────────────────────────────────
# Metadata store for MLflow experiments and Kubeflow Pipeline metadata.
# Three databases created via initdb script on first PVC initialisation.
# ⚠ DEV ONLY: password in variables.tf default — use TF_VAR_postgres_password in CI.

resource "helm_release" "postgresql" {
  name      = "postgresql"
  chart     = "oci://registry-1.docker.io/bitnamicharts/postgresql"
  version   = var.postgresql_chart_version
  namespace = kubernetes_namespace.platform_namespaces["platform"].metadata[0].name

  values = [file("${local.values_dir}/postgresql.yaml")]

  set_sensitive {
    name  = "auth.postgresPassword"
    value = var.postgres_password
  }

  wait          = true
  wait_for_jobs = true
  timeout       = 600

  depends_on = [kubernetes_namespace.platform_namespaces]
}

# ── Redpanda ───────────────────────────────────────────────────────────────────
# Kafka-compatible event bus. Single-broker dev mode; production needs 3 brokers.
# Disable with enable_redpanda=false to save ~1.5GB RAM during early days.

resource "helm_release" "redpanda" {
  count = var.enable_redpanda ? 1 : 0

  name       = "redpanda"
  repository = "https://charts.redpanda.com"
  chart      = "redpanda"
  version    = var.redpanda_chart_version
  namespace  = kubernetes_namespace.platform_namespaces["platform"].metadata[0].name

  values = [file("${local.values_dir}/redpanda.yaml")]

  # Redpanda takes longer to start than typical Helm charts
  wait          = true
  wait_for_jobs = false
  timeout       = 600

  depends_on = [kubernetes_namespace.platform_namespaces]
}

# ── Redpanda topics ────────────────────────────────────────────────────────────
# Create topics via rpk CLI inside the running Redpanda pod.
# Idempotent: checks existence before creating.

resource "null_resource" "redpanda_topics" {
  count = var.enable_redpanda ? 1 : 0

  triggers = {
    topics   = join(",", local.redpanda_topics)
    revision = helm_release.redpanda[0].metadata[0].revision
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      export KUBECONFIG="${local.kubeconfig}"

      echo "Waiting for Redpanda pod redpanda-0 to be Ready..."
      kubectl wait --for=condition=Ready pod/redpanda-0 \
        -n platform --timeout=300s

      echo "Creating Redpanda topics..."
      for topic in ${join(" ", local.redpanda_topics)}; do
        if kubectl exec -n platform redpanda-0 -c redpanda -- \
            rpk topic describe "$topic" > /dev/null 2>&1; then
          echo "  Topic '$topic' already exists — skipping."
        else
          kubectl exec -n platform redpanda-0 -c redpanda -- \
            rpk topic create "$topic" --partitions 3 --replicas 1
          echo "  Topic '$topic' created."
        fi
      done
      echo "All topics ready."
    EOT
  }

  depends_on = [helm_release.redpanda]
}

# ── MLflow ─────────────────────────────────────────────────────────────────────
# Experiment tracking + model registry. Backed by Postgres (mlflow database)
# and MinIO (mlflow-artifacts bucket via S3 protocol).
# Runs in mlops namespace. UI port-forward: kubectl port-forward -n mlops svc/mlflow 5000:5000


# ── MLflow (plain Deployment) ──────────────────────────────────────────────────
# Bypasses the community-charts/mlflow Helm chart due to MLflow 3.7 incompat.
# Pinned to MLflow 2.18.0 (via burakince/mlflow:2.18.0).
# Backed by Postgres (database 'mlflow') + MinIO bucket 'mlflow-artifacts'.

resource "kubernetes_secret" "mlflow" {
  metadata {
    name      = "mlflow-secrets"
    namespace = kubernetes_namespace.platform_namespaces["mlops"].metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "project"                      = "sentinelops"
    }
  }

  data = {
    "backend-store-uri"     = "postgresql://postgres:${var.postgres_password}@postgresql.platform.svc.cluster.local:5432/mlflow"
    "aws-access-key-id"     = var.minio_root_user
    "aws-secret-access-key" = var.minio_root_password
  }

  type = "Opaque"

  depends_on = [
    kubernetes_namespace.platform_namespaces,
    helm_release.postgresql,
    helm_release.minio,
  ]
}

resource "null_resource" "mlflow_deployment" {
  triggers = {
    # Re-apply when the manifest file changes
    manifest_sha = filesha256("${path.module}/../../../manifests/mlflow/deployment.yaml")
    # Re-apply if the secret changes (so the deployment picks up rotated creds)
    secret_uid = kubernetes_secret.mlflow.metadata[0].uid
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      export KUBECONFIG="${local.kubeconfig}"
      echo "Applying MLflow deployment manifest..."
      kubectl apply -f ${path.module}/../../../manifests/mlflow/deployment.yaml
      echo "Waiting for MLflow deployment to be Ready (up to 5 min)..."
      kubectl wait --for=condition=Available --timeout=300s \
        deployment/mlflow -n mlops
      echo "MLflow Ready."
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete -f ${path.module}/../../../manifests/mlflow/deployment.yaml --ignore-not-found=true"
  }

  depends_on = [
    kubernetes_secret.mlflow,
  ]
}
