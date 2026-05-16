# Local Environment

Terraform environment for the local k3d development cluster. Uses the `local-cluster` module to provision a 3-node k3d cluster and a local Docker registry.

## Prerequisites

- Docker Desktop running with WSL2 integration enabled for Ubuntu
- k3d, kubectl, helm installed (run `bash scripts/verify-environment.sh`)
- Ports 80 and 443 free on the host (or override `host_http_port` / `host_https_port`)

## Quick start

```bash
# From repo root — use Makefile targets (recommended)
make up-local       # init + apply
make status-local   # show nodes and pods
make down-local     # destroy

# Or run Terraform directly from this directory
cd infra/terraform/envs/local
terraform init
terraform plan
terraform apply
export KUBECONFIG=$(terraform output -raw kubeconfig_path)
kubectl get nodes
```

## What gets created

| Resource | Details |
|---|---|
| Docker registry | `k3d-registry.localhost` on `localhost:5000` |
| k3d cluster | `sentinelops-local` — 1 server + 2 agents |
| Kubeconfig | `~/.kube/sentinelops-local.yaml` |

## Outputs

```bash
terraform output                              # show all
terraform output -raw kubeconfig_path         # get kubeconfig path
terraform output -raw registry_url_internal   # get in-cluster registry URL
```

## Cleanup

```bash
make down-local   # destroys cluster then registry
```

State is stored in `./terraform.tfstate` (local backend, gitignored).
