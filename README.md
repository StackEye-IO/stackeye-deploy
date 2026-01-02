# StackEye Deploy

Kubernetes Helm charts for StackEye uptime monitoring platform deployment.

## Architecture

```
                    ┌─────────────────────────────────┐
                    │       Cloudflare Pages          │
                    │     (Web Frontend - Free)       │
                    │      app.stackeye.io            │
                    └───────────────┬─────────────────┘
                                    │ API calls
                                    ▼
┌───────────────────────────────────────────────────────────────────┐
│                     a1-ops-prd (On-Prem - Free)                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌──────────┐ │
│  │   ArgoCD    │  │  API Server │  │    CNPG     │  │  Valkey  │ │
│  │ (multi-     │  │ api.stack-  │  │ PostgreSQL  │  │  Cache   │ │
│  │  cluster)   │  │  eye.io     │  │             │  │          │ │
│  └──────┬──────┘  └─────────────┘  └─────────────┘  └──────────┘ │
│         │ manages                                                 │
└─────────┼─────────────────────────────────────────────────────────┘
          │
    ┌─────┴─────────────────────────────┐
    │                                   │
    ▼                                   ▼
┌─────────────────────┐     ┌─────────────────────┐
│  stackeye-nyc3      │     │  stackeye-sfo3      │
│  DOKS ($64/mo)      │     │  DOKS ($64/mo)      │
│  ┌───────────────┐  │     │  ┌───────────────┐  │
│  │    Workers    │  │     │  │    Workers    │  │
│  │  (East Coast) │  │     │  │  (West Coast) │  │
│  │   region=nyc3 │  │     │  │   region=sfo3 │  │
│  └───────────────┘  │     │  └───────────────┘  │
└─────────────────────┘     └─────────────────────┘

Network: Workers connect to on-prem DB via Tailscale VPN
```

## Charts

| Chart | Description | Deploys To |
|-------|-------------|------------|
| `stackeye-api` | API server - REST API for probe management and alerting | On-prem (a1-ops-prd) |
| `stackeye-worker` | Probe worker - executes uptime monitoring checks | DOKS (nyc3, sfo3) |

**Note**: Web frontend is deployed to Cloudflare Pages (not Kubernetes).

## Repository Structure

```
stackeye-deploy/
├── charts/
│   ├── stackeye-api/       # API server Helm chart
│   └── stackeye-worker/    # Worker Helm chart
├── library/
│   └── stackeye-common/    # Shared template library
├── .github/workflows/      # CI/CD pipelines
├── ct.yaml                 # Chart testing config
└── Makefile                # Common commands
```

## Deployment via ArgoCD

Charts are deployed via ArgoCD GitOps from [stackeye-gitops](https://github.com/StackEye-IO/stackeye-gitops).

### Chart Publishing

Charts are automatically published to Harbor OCI registry when chart files change:

```
oci://harbor.support.tools/stackeye/charts/stackeye-api
oci://harbor.support.tools/stackeye/charts/stackeye-worker
```

### ArgoCD Application Structure

| Application | Cluster | Namespace |
|-------------|---------|-----------|
| stackeye-api-{env} | a1-ops-prd (local) | stackeye-{env} |
| stackeye-worker-nyc3-{env} | stackeye-nyc3 (remote) | stackeye-{env} |
| stackeye-worker-sfo3-{env} | stackeye-sfo3 (remote) | stackeye-{env} |

## Prerequisites

- Kubernetes 1.28+
- Helm 3.14+
- [Sealed Secrets controller](https://github.com/bitnami-labs/sealed-secrets) installed
- [cert-manager](https://cert-manager.io/) for TLS
- nginx-ingress controller
- Tailscale for worker → database connectivity

## Manual Chart Installation

```bash
# Update dependencies first
make deps

# Deploy API (on-prem cluster)
helm install stackeye-api charts/stackeye-api \
  -f charts/stackeye-api/values.yaml \
  -n stackeye --create-namespace

# Deploy Worker (DOKS cluster - set region via values)
helm install stackeye-worker charts/stackeye-worker \
  -f charts/stackeye-worker/values.yaml \
  --set worker.region=nyc3 \
  --set worker.regionName="New York" \
  -n stackeye --create-namespace
```

## Secrets Management

This deployment uses [Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) for secrets management.

### Create a Sealed Secret

```bash
# Install kubeseal CLI
brew install kubeseal  # macOS

# Create a secret manifest
kubectl create secret generic stackeye-api-secrets \
  --from-literal=DATABASE_URL='postgres://user:pass@100.x.x.x:5432/db' \
  --from-literal=JWT_SECRET='your-32-char-minimum-secret-key' \
  --from-literal=STRIPE_SECRET_KEY='sk_live_...' \
  --from-literal=STRIPE_WEBHOOK_SECRET='whsec_...' \
  --from-literal=EMAIL_API_KEY='re_...' \
  --dry-run=client -o yaml > secret.yaml

# Seal it (requires access to cluster)
kubeseal --format yaml < secret.yaml > sealedsecret.yaml
```

## Network Connectivity

| Source | Destination | Method |
|--------|-------------|--------|
| Cloudflare Pages | API (a1-ops-prd) | Public HTTPS (api.stackeye.io) |
| Workers (NYC3) | PostgreSQL (a1-ops-prd) | Tailscale VPN |
| Workers (SFO3) | PostgreSQL (a1-ops-prd) | Tailscale VPN |
| ArgoCD (a1-ops-prd) | DOKS clusters | ServiceAccount tokens |

### Tailscale Setup for Workers

Workers running on DOKS clusters connect to on-prem PostgreSQL and Valkey via Tailscale:

1. Install Tailscale on DOKS nodes
2. Configure DATABASE_URL to use Tailscale IP (100.x.x.x)
3. Workers automatically connect via VPN

## Development

### Lint Charts

```bash
make lint
```

### Template Charts (Dry Run)

```bash
# Template API chart
helm template stackeye-api charts/stackeye-api

# Template Worker chart with region
helm template stackeye-worker charts/stackeye-worker --set worker.region=nyc3
```

### Run Chart Tests

```bash
ct lint --config ct.yaml
ct install --config ct.yaml
```

## CI/CD

### GitHub Actions Workflows

- **lint-charts.yml**: Runs on PRs, lints charts and runs install tests
- **publish-charts.yml**: Runs on chart changes, publishes to Harbor OCI registry

### Required Secrets

Configure these in GitHub repository settings:

- `HARBOR_USER`: Harbor registry username
- `HARBOR_PASSWORD`: Harbor registry password

## Dependencies

Charts assume these exist externally:

- **PostgreSQL** - Via [CloudNativePG](https://cloudnative-pg.io/) on a1-ops-prd
- **Valkey** - Via Valkey operator on a1-ops-prd
- **Sealed Secrets Controller** - Bitnami sealed-secrets in each cluster
- **cert-manager** - For TLS certificate automation
- **nginx-ingress** - Ingress controller
- **Tailscale** - For cross-cluster network connectivity

## Related Repositories

| Repository | Purpose |
|------------|---------|
| [stackeye](https://github.com/StackEye-IO/stackeye) | Backend API + Worker code |
| [stackeye-web](https://github.com/StackEye-IO/stackeye-web) | Frontend (Cloudflare Pages) |
| [stackeye-gitops](https://github.com/StackEye-IO/stackeye-gitops) | ArgoCD GitOps config |

## License

Apache 2.0
