# Terraform Module: local-cluster

Provisions a local k3d Kubernetes cluster with an attached Docker registry using the k3d CLI via `null_resource` + `local-exec`. All cluster configuration is tracked in Terraform state, so `terraform destroy` / `terraform apply` produces an identical cluster.

## What it creates

| Resource | Description |
|---|---|
| `k3d-registry.localhost` | Docker registry on `localhost:<registry_port>` — survives cluster recreation |
| k3d cluster | `<cluster_name>` with `server_count` servers + `agent_count` agents |
| kubeconfig | Written to `kubeconfig_path` (isolated, never touches `~/.kube/config`) |

## Usage

```hcl
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
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `cluster_name` | string | `sentinelops-local` | Name of the k3d cluster |
| `server_count` | number | `1` | Control-plane node count (≥ 1) |
| `agent_count` | number | `2` | Worker node count (≥ 0) |
| `registry_port` | number | `5000` | Host port for the local registry |
| `k3s_version` | string | `v1.30.2-k3s2` | Pinned k3s image tag |
| `kubeconfig_path` | string | `~/.kube/sentinelops-local.yaml` | Kubeconfig output path |
| `host_http_port` | number | `80` | Host port → load-balancer port 80 |
| `host_https_port` | number | `443` | Host port → load-balancer port 443 |

## Outputs

| Name | Example value | Description |
|---|---|---|
| `cluster_name` | `sentinelops-local` | Cluster name |
| `kubeconfig_path` | `/home/user/.kube/sentinelops-local.yaml` | Absolute kubeconfig path |
| `registry_url` | `localhost:5000` | Push images here from the host |
| `registry_url_internal` | `k3d-registry.localhost:5000` | Reference images here in pod specs |
| `kubectl_context` | `k3d-sentinelops-local` | kubectl context name |

## After apply

```bash
export KUBECONFIG=~/.kube/sentinelops-local.yaml
kubectl get nodes          # should show 3 Ready nodes
kubectl get pods -A        # should show system pods

# Push an image to the local registry
docker pull nginx:alpine
docker tag nginx:alpine localhost:5000/nginx:alpine
docker push localhost:5000/nginx:alpine

# Reference it in a pod spec using the in-cluster registry URL
# image: k3d-registry.localhost:5000/nginx:alpine
```

## Port conflict resolution

If ports 80 or 443 are occupied on your host, override them:

```hcl
host_http_port  = 8080
host_https_port = 8443
```

## Design notes

- The registry is created **before** the cluster and destroyed **after** it, so pushed images survive cluster recreation via `reset-local`.
- k3d v5 prefixes registry names with `k3d-`, so `registry.localhost` becomes `k3d-registry.localhost` in DNS.
- The module does **not** install Helm charts — that is handled by the `helm-platform` module (Day 2+).
