output "cluster_name" {
  description = "Name of the k3d cluster"
  value       = var.cluster_name
}

output "kubeconfig_path" {
  description = "Absolute path to the cluster kubeconfig file"
  value       = local.kubeconfig_path_expanded
}

output "registry_url" {
  description = "Registry URL accessible from the host (push images here)"
  value       = "localhost:${var.registry_port}"
}

output "registry_url_internal" {
  description = "Registry URL accessible from inside the cluster (use in pod specs)"
  value       = "k3d-${local.registry_short_name}:${var.registry_port}"
}

output "kubectl_context" {
  description = "kubectl context name — use with: kubectl config use-context <value>"
  value       = local.kubectl_context
}
