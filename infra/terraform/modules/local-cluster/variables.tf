variable "cluster_name" {
  description = "Name of the k3d cluster"
  type        = string
  default     = "sentinelops-local"
}

variable "server_count" {
  description = "Number of server (control-plane) nodes"
  type        = number
  default     = 1

  validation {
    condition     = var.server_count >= 1
    error_message = "server_count must be at least 1."
  }
}

variable "agent_count" {
  description = "Number of agent (worker) nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.agent_count >= 0
    error_message = "agent_count must be 0 or greater."
  }
}

variable "registry_port" {
  description = "Host port exposed by the local Docker registry"
  type        = number
  default     = 5000
}

variable "k3s_version" {
  description = "k3s image tag — pinned for reproducibility"
  type        = string
  default     = "v1.30.2-k3s2"
}

variable "kubeconfig_path" {
  description = "Path to write the cluster kubeconfig (~ is expanded)"
  type        = string
  default     = "~/.kube/sentinelops-local.yaml"
}

variable "host_http_port" {
  description = "Host port forwarded to the cluster load-balancer port 80"
  type        = number
  default     = 80
}

variable "host_https_port" {
  description = "Host port forwarded to the cluster load-balancer port 443"
  type        = number
  default     = 443
}
