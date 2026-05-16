module "local_cluster" {
  source = "../../modules/local-cluster"

  cluster_name    = "sentinelops-local"
  server_count    = 1
  agent_count     = 2
  registry_port   = 5000
  k3s_version     = "v1.30.2-k3s2"
  kubeconfig_path = "~/.kube/sentinelops-local.yaml"
  host_http_port  = 80
  host_https_port = 443
}

# ── Outputs (visible via `terraform output`) ───────────────────────────────────

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
