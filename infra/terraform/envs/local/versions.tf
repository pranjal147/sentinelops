terraform {
  required_version = ">= 1.7"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
  }
}

# Kubernetes provider — points at the local k3d cluster kubeconfig.
# The cluster must exist before running terraform apply on the helm-platform module.
# Workflow: make up-local first, then make up-foundation.
provider "kubernetes" {
  config_path    = pathexpand("~/.kube/sentinelops-local.yaml")
  config_context = "k3d-sentinelops-local"
}

provider "helm" {
  kubernetes {
    config_path    = pathexpand("~/.kube/sentinelops-local.yaml")
    config_context = "k3d-sentinelops-local"
  }
}
