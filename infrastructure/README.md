# StackEye Infrastructure

Infrastructure components for StackEye managed via kubectl (not Helm).

## Quick Start

Use the deployment script for all infrastructure operations:

```bash
# Deploy all infrastructure to dev on on-prem cluster
./scripts/deploy-infra.sh dev onprem all

# Deploy specific component
./scripts/deploy-infra.sh dev onprem cnpg

# Dry-run mode (shows commands without executing)
DRY_RUN=true ./scripts/deploy-infra.sh dev onprem all
```

## Deployment Script

**Location**: `scripts/deploy-infra.sh`

### Usage

```bash
./scripts/deploy-infra.sh <environment> <cluster> [component]
```

### Arguments

| Argument | Values | Description |
|----------|--------|-------------|
| environment | `dev`, `stg`, `prd` | Target environment |
| cluster | `onprem`, `nyc3`, `sfo3` | Target Kubernetes cluster |
| component | `cnpg`, `valkey`, `monitoring`, `tailscale`, `secrets`, `all` | Component to deploy (default: all) |

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `KUBECONFIG_ONPREM` | `~/.kube/config` | Path to on-prem kubeconfig |
| `KUBECONFIG_NYC3` | `~/.kube/mattox/stackeye-nyc3` | Path to NYC3 DOKS kubeconfig |
| `KUBECONFIG_SFO3` | `~/.kube/mattox/stackeye-sfo3` | Path to SFO3 DOKS kubeconfig |
| `DRY_RUN` | `false` | Set to `true` to show commands without executing |

### Examples

```bash
# Deploy all infra to dev on on-prem
./scripts/deploy-infra.sh dev onprem

# Deploy only CNPG to staging
./scripts/deploy-infra.sh stg onprem cnpg

# Deploy Tailscale connector to NYC3 cluster
./scripts/deploy-infra.sh dev nyc3 tailscale

# Deploy secrets to SFO3 cluster
./scripts/deploy-infra.sh dev sfo3 secrets

# Preview what would be deployed (dry-run)
DRY_RUN=true ./scripts/deploy-infra.sh prd onprem all
```

---

## Components

### CNPG (CloudNativePG) - On-Prem Only

TimescaleDB-enabled PostgreSQL clusters.

| Environment | Namespace | Instances | Storage |
|-------------|-----------|-----------|---------|
| dev | stackeye-dev | 1 | 8Gi |
| stg | stackeye-stg | 2 | 16Gi |
| prd | stackeye-prd | 3 | 32Gi |

**Directory**: `cnpg/`
- `base/` - Namespace definitions
- `dev/`, `stg/`, `prd/` - Environment-specific cluster configs

### Valkey (Redis) - On-Prem Only

In-memory cache clusters using Valkey (Redis-compatible).

| Environment | Namespace | Mode |
|-------------|-----------|------|
| dev | stackeye-dev | Standalone |
| stg | stackeye-stg | Standalone |
| prd | stackeye-prd | Standalone |

**Directory**: `valkey/`
- `dev/`, `stg/`, `prd/` - Environment-specific deployments

### Monitoring - On-Prem Only

Prometheus and Grafana stack for observability.

**Directory**: `monitoring/`
- `base/` - Shared resources (namespaces, RBAC)
- `prometheus/` - Prometheus server and config
- `grafana/` - Grafana dashboards and datasources

### Tailscale - Regional Clusters Only

Tailscale connectors for secure mesh networking from DOKS clusters to on-prem.

**Directory**: `tailscale/`
- `nyc3/` - NYC3 cluster connector
- `sfo3/` - SFO3 cluster connector

### Secrets - All Clusters

Sealed secrets for each cluster.

**Directory**: `secrets/`
- `a1-ops-prd/` - On-prem cluster secrets
- `stackeye-nyc3/` - NYC3 DOKS secrets
- `stackeye-sfo3/` - SFO3 DOKS secrets

Secret files are named: `sealed-*-{env}.yaml` (e.g., `sealed-api-secrets-dev.yaml`)

---

## Cluster Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          On-Prem (a1-ops-prd)                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌────────────┐ │
│  │    CNPG     │  │   Valkey    │  │ Monitoring  │  │   API +    │ │
│  │ PostgreSQL  │  │   (Redis)   │  │ Prometheus  │  │    Web     │ │
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

---

## Prerequisites

### 1. Kubeconfig Files

Ensure kubeconfig files exist for each cluster:

```bash
# On-prem (default)
~/.kube/config

# DOKS clusters
~/.kube/mattox/stackeye-nyc3
~/.kube/mattox/stackeye-sfo3
```

Or set environment variables:
```bash
export KUBECONFIG_ONPREM=~/.kube/config
export KUBECONFIG_NYC3=~/.kube/mattox/stackeye-nyc3
export KUBECONFIG_SFO3=~/.kube/mattox/stackeye-sfo3
```

### 2. CNPG Backup Credentials (S3)

Create the `postgres-backup-credentials` secret before deploying CNPG:

```bash
# Use the template
cp cnpg/secrets-template.yaml cnpg/secrets-local.yaml
# Edit with your S3 credentials, then:
kubectl apply -f cnpg/secrets-local.yaml
```

Or create directly:
```bash
for ns in stackeye-dev stackeye-stg stackeye-prd; do
  kubectl create secret generic postgres-backup-credentials -n $ns \
    --from-literal=ACCESS_KEY_ID="<ACCESS_KEY>" \
    --from-literal=SECRET_ACCESS_KEY="<SECRET_KEY>"
done
```

### 3. Tailscale Auth Keys

Create Tailscale auth keys before deploying connectors:

```bash
# Use the template
cp tailscale/secrets-template.yaml tailscale/secrets-local.yaml
# Edit with your Tailscale auth key, then:
kubectl apply -f tailscale/secrets-local.yaml
```

### 4. Sealed Secrets Controller

The Bitnami Sealed Secrets controller must be installed on each cluster:

```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system
```

---

## Verification Commands

### CNPG
```bash
# Check cluster status
kubectl get clusters.postgresql.cnpg.io -n stackeye-dev

# Check pods
kubectl get pods -n stackeye-dev -l cnpg.io/cluster=stackeye-db

# Verify TimescaleDB
kubectl exec -it stackeye-db-1 -n stackeye-dev -- psql -U postgres -c "\\dx"
```

### Valkey
```bash
# Check deployment
kubectl get pods -n stackeye-dev -l app=valkey

# Test connection
kubectl exec -it deploy/valkey -n stackeye-dev -- redis-cli ping
```

### Monitoring
```bash
# Check Prometheus
kubectl get pods -n monitoring -l app=prometheus

# Check Grafana
kubectl get pods -n monitoring -l app=grafana
```

### Tailscale
```bash
# Check connector status (NYC3)
kubectl get pods -n tailscale -l app=tailscale-connector

# Check Tailscale connection
kubectl logs -n tailscale -l app=tailscale-connector --tail=50
```

### Secrets
```bash
# List sealed secrets
kubectl get sealedsecrets -n stackeye-dev

# Check if secrets were unsealed
kubectl get secrets -n stackeye-dev | grep stackeye
```

---

## Connection Details

### PostgreSQL (CNPG)

| Environment | Service | Port |
|-------------|---------|------|
| dev | `stackeye-db-rw.stackeye-dev.svc` | 5432 |
| stg | `stackeye-db-rw.stackeye-stg.svc` | 5432 |
| prd | `stackeye-db-rw.stackeye-prd.svc` | 5432 |

Credentials are in the auto-generated secret `stackeye-db-app`.

### Valkey (Redis)

| Environment | Service | Port |
|-------------|---------|------|
| dev | `valkey.stackeye-dev.svc` | 6379 |
| stg | `valkey.stackeye-stg.svc` | 6379 |
| prd | `valkey.stackeye-prd.svc` | 6379 |

---

## Directory Structure

```
infrastructure/
├── README.md                    # This file
├── worker-secrets-template.yaml # Template for worker secrets
├── cnpg/
│   ├── base/                    # Namespace definitions
│   ├── dev/                     # Dev cluster config
│   ├── stg/                     # Staging cluster config
│   ├── prd/                     # Production cluster config
│   └── secrets-template.yaml    # S3 backup credentials template
├── valkey/
│   ├── dev/                     # Dev deployment
│   ├── stg/                     # Staging deployment
│   └── prd/                     # Production deployment
├── monitoring/
│   ├── base/                    # Shared resources
│   ├── prometheus/              # Prometheus stack
│   └── grafana/                 # Grafana stack
├── sealed-secrets/
│   └── README.md                # Sealed secrets documentation
├── secrets/
│   ├── a1-ops-prd/              # On-prem sealed secrets
│   ├── stackeye-nyc3/           # NYC3 DOKS sealed secrets
│   └── stackeye-sfo3/           # SFO3 DOKS sealed secrets
└── tailscale/
    ├── nyc3/                    # NYC3 connector
    ├── sfo3/                    # SFO3 connector
    └── secrets-template.yaml    # Auth key template
```

---

## Troubleshooting

### CNPG cluster not starting
```bash
# Check operator logs
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg

# Check cluster events
kubectl describe cluster stackeye-db -n stackeye-dev
```

### Secrets not unsealing
```bash
# Check sealed-secrets controller
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Re-seal secret if controller was reinstalled
kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system < secret.yaml > sealed-secret.yaml
```

### Tailscale not connecting
```bash
# Check connector logs
kubectl logs -n tailscale -l app=tailscale-connector

# Verify auth key is valid
# Regenerate auth key in Tailscale admin console if expired
```
