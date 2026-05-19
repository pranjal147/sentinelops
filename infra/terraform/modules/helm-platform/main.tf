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
# Uses the official MinIO chart (charts.min.io) — NOT Bitnami.
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
#
# Chart: OCI Bitnami catalog (still works for the CHART itself).
# Image: bitnamilegacy/postgresql (Bitnami moved versioned images here in 2025).
# See: https://github.com/bitnami/charts/issues/35164
#
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

# ── Kubeflow Pipelines (standalone 2.3.0) ─────────────────────────────────────
# Uses upstream platform-agnostic manifest (bundled MySQL + MinIO inside kubeflow).
# Does NOT modify platform/* or mlops/* — separate namespace only.
# See docs/CLAUDE_CODE_HANDOFF.md

resource "null_resource" "kfp_crds" {
  count = var.enable_kfp ? 1 : 0

  triggers = {
    kfp_version = var.kfp_version
    kubeconfig  = local.kubeconfig
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      export KUBECONFIG="${local.kubeconfig}"
      kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=${var.kfp_version}"
      kubectl wait --for=condition=Established --timeout=120s \
        crd/applications.app.k8s.io \
        crd/scheduledworkflows.kubeflow.org \
        crd/viewers.kubeflow.org \
        crd/workflows.argoproj.io \
        crd/workflowtemplates.argoproj.io \
        crd/cronworkflows.argoproj.io
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      export KUBECONFIG="${self.triggers.kubeconfig}"
      kubectl delete -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=${self.triggers.kfp_version}" \
        --ignore-not-found --wait=false || true
    EOT
  }

  depends_on = [
    helm_release.minio,
    helm_release.postgresql,
    helm_release.cert_manager,
  ]
}

resource "null_resource" "kfp_platform" {
  count = var.enable_kfp ? 1 : 0

  triggers = {
    kfp_version   = var.kfp_version
    crd_id        = null_resource.kfp_crds[0].id
    kubeconfig    = local.kubeconfig
    kustomize_dir = "${path.module}/../../../kustomize/kubeflow-pipelines"
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    # Use the lean kustomize overlay (infra/kustomize/kubeflow-pipelines/) instead of
    # platform-agnostic. This avoids the bundled MinIO deployment whose image
    # (gcr.io/ml-pipeline/minio:RELEASE.2019-08-14T20-37-41Z-license-compliance) was
    # purged when gcr.io shut down in March 2025. The overlay routes KFP artifact
    # storage to the Day 2 platform MinIO via an ExternalName service.
    command = <<-EOT
      set -euo pipefail
      export KUBECONFIG="${local.kubeconfig}"
      kubectl apply -k "${path.module}/../../../kustomize/kubeflow-pipelines"
      bash "${path.module}/../../../../scripts/kfp-wait-deployments.sh"
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      export KUBECONFIG="${self.triggers.kubeconfig}"
      kubectl delete -k "${self.triggers.kustomize_dir}" \
        --ignore-not-found --wait=false || true
      kubectl delete namespace kubeflow --ignore-not-found --wait=true --timeout=300s || true
    EOT
  }

  depends_on = [null_resource.kfp_crds]
}