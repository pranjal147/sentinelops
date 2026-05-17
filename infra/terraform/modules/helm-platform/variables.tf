variable "kubeconfig_path" {
  description = "Absolute path to the cluster kubeconfig (used by local-exec provisioners)"
  type        = string
  default     = "~/.kube/sentinelops-local.yaml"
}

variable "minio_root_user" {
  description = "MinIO root (admin) username — DEV ONLY, change for production"
  type        = string
  sensitive   = true
  default     = "minio"
}

variable "minio_root_password" {
  description = "MinIO root password — DEV ONLY, change for production"
  type        = string
  sensitive   = true
  default     = "minio123"
}

variable "postgres_password" {
  description = "PostgreSQL superuser password — DEV ONLY, change for production"
  type        = string
  sensitive   = true
  default     = "postgres123"
}

variable "enable_redpanda" {
  description = "Whether to install Redpanda (disable to save RAM during early days)"
  type        = bool
  default     = true
}

# ── Chart versions (pinned for reproducibility) ────────────────────────────────

variable "cert_manager_chart_version" {
  description = "Jetstack cert-manager Helm chart version"
  type        = string
  default     = "v1.16.2"
}

variable "minio_chart_version" {
  description = "Official MinIO Helm chart version (charts.min.io)"
  type        = string
  default     = "5.4.0"
}

variable "postgresql_chart_version" {
  description = "Bitnami PostgreSQL Helm chart version (OCI catalog)"
  type        = string
  default     = "18.6.6"
}

variable "redpanda_chart_version" {
  description = "Redpanda Helm chart version"
  type        = string
  default     = "5.9.14"
}
