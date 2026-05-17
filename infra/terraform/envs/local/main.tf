# ── Cluster ────────────────────────────────────────────────────────────────────
# Provision with: make up-local   (targets this module only)
module "local_cluster" {
  source = "../../modules/local-cluster"

  cluster_name    = "sentinelops-local"
  server_count    = 1
  agent_count     = 2
  registry_port   = 5000
  k3s_version     = "v1.30.2-k3s2"
  kubeconfig_path = "~/.kube/sentinelops-local.yaml"
  host_http_port  = 8080
  host_https_port = 8443
}

# ── Foundation (Helm) ──────────────────────────────────────────────────────────
# Provision with: make up-foundation  (runs after cluster is up)
module "helm_platform" {
  source = "../../modules/helm-platform"

  kubeconfig_path     = module.local_cluster.kubeconfig_path
  minio_root_user     = "minio"
  minio_root_password = "minio123"
  postgres_password   = "postgres123"
  enable_redpanda     = true

  depends_on = [module.local_cluster]
}

# ── Cluster outputs ────────────────────────────────────────────────────────────

output "cluster_name" {
  description = "k3d cluster name"
  value       = module.local_cluster.cluster_name
}

output "kubeconfig_path" {
  description = "Absolute path to kubeconfig — export KUBECONFIG=$(terraform output -raw kubeconfig_path)"
  value       = module.local_cluster.kubeconfig_path
}

output "registry_url" {
  description = "Push images here from the host"
  value       = module.local_cluster.registry_url
}

output "registry_url_internal" {
  description = "Use this URL in pod specs (in-cluster reference)"
  value       = module.local_cluster.registry_url_internal
}

output "kubectl_context" {
  description = "kubectl context — kubectl config use-context <value>"
  value       = module.local_cluster.kubectl_context
}

# ── Foundation outputs ─────────────────────────────────────────────────────────

output "minio_endpoint" {
  description = "MinIO S3 API (in-cluster)"
  value       = module.helm_platform.minio_endpoint
}

output "postgres_host" {
  description = "PostgreSQL host (in-cluster)"
  value       = module.helm_platform.postgres_host
}

output "redpanda_brokers" {
  description = "Redpanda broker (in-cluster)"
  value       = module.helm_platform.redpanda_brokers
}

output "created_topics" {
  description = "Redpanda topics"
  value       = module.helm_platform.created_topics
}
