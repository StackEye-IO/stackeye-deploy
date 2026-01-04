# StackEye Deploy

Infrastructure manifests for StackEye uptime monitoring platform.

## Purpose

This repository contains **infrastructure-only** manifests for StackEye. Application Helm charts have been migrated to their respective repositories and are deployed via CI pipelines.

| What | Where |
|------|-------|
| API + Worker Helm charts | [stackeye/deploy/charts/](https://github.com/StackEye-IO/stackeye) |
| Web Helm chart | [stackeye-web/deploy/charts/](https://github.com/StackEye-IO/stackeye-web) |
| Infrastructure manifests | **This repo** (`infrastructure/`) |

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     a1-ops-prd (On-Prem)                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌────────────┐ │
│  │    CNPG     │  │   Valkey    │  │ Monitoring  │  │  API + Web │ │
│  │ PostgreSQL  │  │   (Redis)   │  │ Prometheus  │  │  (Helm)    │ │
│  └─────────────┘  └─────────────┘  │  Grafana    │  └────────────┘ │
│                                     └─────────────┘                  │
└─────────────────────────────────────────────────────────────────────┘
         ▲                                      ▲
         │ Tailscale Mesh                       │
         │                                      │
┌────────┴────────┐                   ┌────────┴────────┐
│   DOKS NYC3     │                   │   DOKS SFO3     │
│  ┌───────────┐  │                   │  ┌───────────┐  │
│  │ Tailscale │  │                   │  │ Tailscale │  │
│  │ Connector │  │                   │  │ Connector │  │
│  └───────────┘  │                   │  └───────────┘  │
│  ┌───────────┐  │                   │  ┌───────────┐  │
│  │  Worker   │  │                   │  │  Worker   │  │
│  │ (Probes)  │  │                   │  │ (Probes)  │  │
│  └───────────┘  │                   │  └───────────┘  │
└─────────────────┘                   └─────────────────┘
```

## Repository Structure

```
stackeye-deploy/
├── infrastructure/         # Infrastructure manifests
│   ├── cnpg/               # CloudNativePG PostgreSQL clusters
│   ├── valkey/             # Valkey (Redis) cache
│   ├── monitoring/         # Prometheus + Grafana
│   ├── tailscale/          # Tailscale connectors (NYC3, SFO3)
│   ├── secrets/            # Sealed secrets per cluster
│   └── README.md           # Detailed infrastructure docs
├── scripts/
│   └── deploy-infra.sh     # Infrastructure deployment script
└── .github/workflows/      # CI pipelines (if any)
```

## Quick Start

Deploy infrastructure using the provided script:

```bash
# Deploy all infrastructure to dev on on-prem
./scripts/deploy-infra.sh dev onprem all

# Deploy specific component
./scripts/deploy-infra.sh dev onprem cnpg

# Deploy Tailscale to regional cluster
./scripts/deploy-infra.sh dev nyc3 tailscale

# Dry-run mode
DRY_RUN=true ./scripts/deploy-infra.sh prd onprem all
```

See [infrastructure/README.md](infrastructure/README.md) for detailed documentation.

## Deployment Model

### Application Deployments (CI-Driven)

Application deployments are handled via CI pipelines in each repo:

| Repository | Trigger | Deploys |
|------------|---------|---------|
| `stackeye/` | Tag push (`v*`) | API + Worker via Helm |
| `stackeye-web/` | Tag push (`v*`) | Web frontend via Helm |

**Tag convention:**
- `v0.1.0` → deploys to `stackeye-dev`
- `v0.1.0-staging` → deploys to `stackeye-stg`
- `v0.1.0-prod` → deploys to `stackeye-prd`

### Infrastructure Deployments (Manual)

Infrastructure is deployed manually using `scripts/deploy-infra.sh`:

| Component | Cluster | Environments |
|-----------|---------|--------------|
| CNPG | onprem | dev, stg, prd |
| Valkey | onprem | dev, stg, prd |
| Monitoring | onprem | shared |
| Tailscale | nyc3, sfo3 | shared |
| Secrets | all | per-environment |

## Prerequisites

- Kubernetes 1.28+
- Helm 3.14+ (for app deployments)
- kubectl access to all clusters
- [Sealed Secrets controller](https://github.com/bitnami-labs/sealed-secrets)
- [CloudNativePG operator](https://cloudnative-pg.io/)
- Tailscale account and auth keys

## Kubeconfig Setup

Set these environment variables or use defaults:

```bash
export KUBECONFIG_ONPREM=~/.kube/config
export KUBECONFIG_NYC3=~/.kube/mattox/stackeye-nyc3
export KUBECONFIG_SFO3=~/.kube/mattox/stackeye-sfo3
```

## Secrets Management

Secrets are managed via [Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets).

### Create a New Sealed Secret

```bash
# Create a secret manifest
kubectl create secret generic my-secret \
  --from-literal=KEY='value' \
  --dry-run=client -o yaml > secret.yaml

# Seal it for the target cluster
kubeseal --controller-name=sealed-secrets \
         --controller-namespace=kube-system \
         < secret.yaml > sealed-secret.yaml

# Apply
kubectl apply -f sealed-secret.yaml
```

Sealed secrets are stored in `infrastructure/secrets/<cluster>/`.

## Related Repositories

| Repository | Purpose |
|------------|---------|
| [stackeye](https://github.com/StackEye-IO/stackeye) | Backend API + Worker (includes Helm charts) |
| [stackeye-web](https://github.com/StackEye-IO/stackeye-web) | Frontend (includes Helm chart) |

## Migration Notes

This repository was previously named `stackeye-gitops` and used ArgoCD for deployments. As of January 2026:

- **Application charts** moved to `stackeye/deploy/charts/` and `stackeye-web/deploy/charts/`
- **Deployments** now triggered by CI pipelines on tag push
- **Infrastructure** remains here, deployed via `scripts/deploy-infra.sh`
- **ArgoCD** no longer used for StackEye deployments

## License

Apache 2.0
