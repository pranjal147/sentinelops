output "minio_endpoint" {
  description = "MinIO S3 API endpoint (in-cluster)"
  value       = "minio.platform.svc.cluster.local:9000"
}

output "minio_console_url" {
  description = "MinIO Console — port-forward to access: kubectl port-forward svc/minio 9001:9001 -n platform"
  value       = "http://localhost:9001"
}

output "postgres_host" {
  description = "PostgreSQL host (in-cluster)"
  value       = "postgresql.platform.svc.cluster.local"
}

output "postgres_databases" {
  description = "Pre-created PostgreSQL databases"
  value       = ["mlflow", "kfp", "metadata"]
}

output "redpanda_brokers" {
  description = "Redpanda Kafka-compatible broker (in-cluster)"
  value       = var.enable_redpanda ? "redpanda.platform.svc.cluster.local:9092" : ""
}

output "created_topics" {
  description = "Redpanda topics created by Terraform"
  value       = var.enable_redpanda ? ["inference-events", "incidents", "audit", "human-queue"] : []
}

output "namespaces" {
  description = "All namespaces managed by this module"
  value       = ["cert-manager", "platform", "mlops", "serving", "observability", "apps", "chaos-mesh"]
}

output "mlflow_endpoint" {
  description = "MLflow tracking server endpoint (in-cluster)"
  value       = "http://mlflow.mlops.svc.cluster.local:5000"
}

output "mlflow_ui_port_forward" {
  description = "Command to access MLflow UI"
  value       = "kubectl port-forward -n mlops svc/mlflow 5000:5000"
}

# (mlflow outputs may already exist — these are idempotent)
