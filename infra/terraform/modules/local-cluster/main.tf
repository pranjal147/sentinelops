locals {
  kubeconfig_path_expanded = pathexpand(var.kubeconfig_path)
  # k3d prefixes registry names with "k3d-", so "registry.localhost" → "k3d-registry.localhost"
  registry_short_name = "registry.localhost"
  kubectl_context     = "k3d-${var.cluster_name}"
}

# ── Local Docker registry ───────────────────────────────────────────────────────
# Created independently of the cluster so cached images survive cluster recreation.
resource "null_resource" "k3d_registry" {
  triggers = {
    registry_name = local.registry_short_name
    registry_port = tostring(var.registry_port)
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      if k3d registry list 2>/dev/null | grep -q "k3d-${local.registry_short_name}"; then
        echo "Registry k3d-${local.registry_short_name} already exists — skipping."
      else
        k3d registry create "${local.registry_short_name}" --port ${var.registry_port}
        echo "Registry k3d-${local.registry_short_name} created on port ${var.registry_port}."
      fi
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      k3d registry delete "${self.triggers.registry_name}" \
        && echo "Registry k3d-${self.triggers.registry_name} deleted." \
        || echo "Registry k3d-${self.triggers.registry_name} not found — skipping."
    EOT
  }
}

# ── k3d cluster ────────────────────────────────────────────────────────────────
# 1 server + N agents, connected to the local registry, with ports 80/443 forwarded
# through the k3d load balancer to traefik inside the cluster.
resource "null_resource" "k3d_cluster" {
  triggers = {
    cluster_name    = var.cluster_name
    server_count    = tostring(var.server_count)
    agent_count     = tostring(var.agent_count)
    registry_port   = tostring(var.registry_port)
    k3s_version     = var.k3s_version
    host_http_port  = tostring(var.host_http_port)
    host_https_port = tostring(var.host_https_port)
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      k3d cluster create "${var.cluster_name}" \
        --servers ${var.server_count} \
        --agents ${var.agent_count} \
        --registry-use k3d-${local.registry_short_name}:${var.registry_port} \
        --port "${var.host_http_port}:80@loadbalancer" \
        --port "${var.host_https_port}:443@loadbalancer" \
        --image "rancher/k3s:${var.k3s_version}" \
        --wait \
        --timeout 120s
      echo "Cluster ${var.cluster_name} is ready."
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      k3d cluster delete "${self.triggers.cluster_name}" \
        && echo "Cluster ${self.triggers.cluster_name} deleted." \
        || echo "Cluster ${self.triggers.cluster_name} not found — skipping."
    EOT
  }

  depends_on = [null_resource.k3d_registry]
}

# ── Export kubeconfig ──────────────────────────────────────────────────────────
# Writes an isolated kubeconfig so this cluster never pollutes ~/.kube/config.
resource "null_resource" "kubeconfig_export" {
  triggers = {
    cluster_id      = null_resource.k3d_cluster.id
    kubeconfig_path = local.kubeconfig_path_expanded
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      mkdir -p "$(dirname "${local.kubeconfig_path_expanded}")"
      k3d kubeconfig get "${var.cluster_name}" > "${local.kubeconfig_path_expanded}"
      chmod 600 "${local.kubeconfig_path_expanded}"
      echo "Kubeconfig written to ${local.kubeconfig_path_expanded}"
      echo "Run:  export KUBECONFIG=${local.kubeconfig_path_expanded}"
    EOT
  }

  depends_on = [null_resource.k3d_cluster]
}
