# SentinelOps

> A production-grade, self-healing ML inference platform on Kubernetes — trained models serve predictions via KServe + Istio while a Claude-powered remediation agent continuously monitors platform health, detects failures (latency spikes, model drift, resource exhaustion, prediction anomalies), and autonomously remediates them under Open Policy Agent safety guardrails.

<!-- Badges — populated on Day 20 -->
![Build](https://img.shields.io/badge/build-placeholder-lightgrey)
![License](https://img.shields.io/badge/license-MIT-blue)
![Phase](https://img.shields.io/badge/phase-Day%200%2F20-orange)

---

## Quick Links

| | |
|---|---|
| Architecture diagram | `docs/images/architecture.png` *(Day 3)* |
| Demo video | *(Day 20)* |
| Build blog | *(Day 20)* |
| Daily log | [docs/daily-log.md](docs/daily-log.md) |

---

## Tech Stack

| Layer | Technology |
|---|---|
| Infra (local) | k3d, Terraform, Helm |
| Infra (cloud) | AWS EKS, VPC, IRSA, ECR, S3 |
| ML training | Kubeflow Pipelines, MLflow, LightGBM, DistilBERT |
| Model serving | KServe, Istio, FastAPI transformer |
| Event bus | Redpanda (Kafka-compatible) |
| Observability | Prometheus, Grafana, Loki |
| Anomaly detection | Isolation Forest, Prophet |
| AI remediation | Claude API (tool-use), OPA Rego policies |
| GitOps | ArgoCD |
| Chaos engineering | Chaos Mesh |

---

## Project Structure

```
sentinelops/
├── infra/
│   ├── terraform/
│   │   ├── modules/          # local-cluster, aws-network, aws-eks, aws-data, helm-platform
│   │   └── envs/             # local/, aws/
│   └── helm-values/          # Per-chart value overrides
├── pipelines/
│   ├── fraud-lgbm/           # LightGBM fraud detection Kubeflow pipeline
│   └── sentiment-distilbert/ # DistilBERT sentiment Kubeflow pipeline
├── serving/
│   ├── transformer/          # FastAPI prediction logger
│   └── inference-services/   # KServe InferenceService manifests
├── platform/
│   ├── anomaly-detector/     # Isolation Forest + Prophet service
│   ├── remediation-agent/    # Claude tool-use agent
│   └── opa-policies/         # Rego safety policies
├── chaos/                    # Chaos Mesh experiment manifests
├── docs/
│   ├── daily-log.md
│   └── images/
├── scripts/                  # verify-environment.sh, day-0-check.sh
├── .github/workflows/        # CI/CD pipelines
├── Makefile
├── .cursorrules
└── .gitignore
```

---

## Quickstart

> Full instructions available on Day 20. Placeholder below.

```bash
# Prerequisites: WSL2 Ubuntu 22.04, Docker Desktop, all tools from scripts/verify-environment.sh
git clone https://github.com/<your-org>/sentinelops.git
cd sentinelops
bash scripts/verify-environment.sh   # verify tooling
make cluster-up                      # spin up k3d cluster (Day 1+)
make platform-up                     # deploy full platform stack (Day 8+)
```

---

## Day-by-Day Progress

See [docs/daily-log.md](docs/daily-log.md) for detailed daily notes, blockers, and time spent.

| Days | Theme |
|---|---|
| 0 | Environment bootstrap |
| 1–2 | Terraform k3d cluster + platform base |
| 3–4 | Kubeflow + MLflow + model training |
| 5–6 | KServe + Istio model serving |
| 7 | FastAPI transformer + Redpanda |
| 8–9 | Anomaly detector service |
| 10–11 | Claude remediation agent + OPA policies |
| 12 | Chaos Mesh + full local demo |
| 13–14 | AWS EKS migration |
| 15–16 | AWS data services (S3, ECR, RDS) |
| 17–18 | ArgoCD GitOps + full CI/CD |
| 19 | Load testing + chaos on EKS |
| 20 | Polish, docs, demo video |

---

## License

MIT
