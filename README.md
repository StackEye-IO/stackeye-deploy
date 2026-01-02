# StackEye Deploy

Kubernetes Helm charts for StackEye uptime monitoring platform deployment.

## Charts

| Chart | Description | Version |
|-------|-------------|---------|
| `stackeye-api` | API server - REST API for probe management and alerting | 0.1.0 |
| `stackeye-worker` | Probe worker - executes uptime monitoring checks | 0.1.0 |
| `stackeye-web` | Web dashboard - Next.js frontend application | 0.1.0 |

## Repository Structure

```
stackeye-deploy/
├── charts/
│   ├── stackeye-api/       # API server Helm chart
│   ├── stackeye-worker/    # Worker Helm chart
│   └── stackeye-web/       # Web dashboard Helm chart
├── library/
│   └── stackeye-common/    # Shared template library
├── environments/
│   ├── dev/                # Development values
│   ├── staging/            # Staging values
│   └── prod/               # Production values
├── .github/workflows/      # CI/CD pipelines
├── helmfile.yaml           # Umbrella deployment
├── ct.yaml                 # Chart testing config
└── Makefile                # Common commands
```

## Quick Start

### Prerequisites

- Kubernetes 1.28+
- Helm 3.14+
- Helmfile 0.160+
- [Sealed Secrets controller](https://github.com/bitnami-labs/sealed-secrets) installed
- [cert-manager](https://cert-manager.io/) for TLS
- nginx-ingress controller

### Deploy All Charts

```bash
# Deploy to development
helmfile -e dev apply

# Deploy to staging
helmfile -e staging apply

# Deploy to production
helmfile -e prod apply
```

### Deploy Individual Charts

```bash
# Update dependencies first
make deps

# Deploy API
helm install stackeye-api charts/stackeye-api \
  -f charts/stackeye-api/values.yaml \
  -f charts/stackeye-api/values-dev.yaml \
  -n stackeye-dev --create-namespace

# Deploy Worker
helm install stackeye-worker charts/stackeye-worker \
  -f charts/stackeye-worker/values.yaml \
  -f charts/stackeye-worker/values-dev.yaml \
  -n stackeye-dev

# Deploy Web
helm install stackeye-web charts/stackeye-web \
  -f charts/stackeye-web/values.yaml \
  -f charts/stackeye-web/values-dev.yaml \
  -n stackeye-dev
```

## Secrets Management

This deployment uses [Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) for secrets management.

### Create a Sealed Secret

```bash
# Install kubeseal CLI
brew install kubeseal  # macOS
# or
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.5/kubeseal-0.24.5-linux-amd64.tar.gz

# Create a secret manifest
kubectl create secret generic stackeye-api-secrets \
  --from-literal=DATABASE_URL='postgres://user:pass@host:5432/db' \
  --from-literal=JWT_SECRET='your-32-char-minimum-secret-key' \
  --from-literal=STRIPE_SECRET_KEY='sk_live_...' \
  --from-literal=STRIPE_WEBHOOK_SECRET='whsec_...' \
  --from-literal=EMAIL_API_KEY='re_...' \
  --dry-run=client -o yaml > secret.yaml

# Seal it (requires access to cluster)
kubeseal --format yaml < secret.yaml > sealedsecret.yaml

# Copy the encryptedData section to your values file
```

### Environment-Specific Secrets

Each environment has its own sealed secrets:

- `charts/stackeye-api/values-dev.yaml` - Development (plain secrets OK)
- `charts/stackeye-api/values-staging.yaml` - Staging (sealed secrets required)
- `charts/stackeye-api/values-prod.yaml` - Production (sealed secrets required)

## Multi-Region Worker Deployment

For production, workers can be deployed across multiple regions:

```yaml
# values-prod.yaml
mode: multi-region
regions:
  - id: nyc3
    name: "New York"
    enabled: true
    replicaCount: 3
  - id: sfo3
    name: "San Francisco"
    enabled: true
    replicaCount: 3
  - id: chi1
    name: "Chicago"
    enabled: true
    replicaCount: 3
```

## Development

### Lint Charts

```bash
make lint
```

### Template Charts (Dry Run)

```bash
# Template with dev values
make template ENV=dev

# Template with prod values
make template ENV=prod
```

### Run Chart Tests

```bash
ct lint --config ct.yaml
ct install --config ct.yaml
```

## CI/CD

### GitHub Actions Workflows

- **lint-charts.yml**: Runs on PRs, lints charts and runs install tests
- **publish-charts.yml**: Runs on push to main, publishes to Harbor OCI registry

### Required Secrets

Configure these in GitHub repository settings:

- `HARBOR_USER`: Harbor registry username
- `HARBOR_PASSWORD`: Harbor registry password

## Dependencies

Charts assume these exist externally:

- **PostgreSQL** - Via [CloudNativePG](https://cloudnative-pg.io/) or managed database
- **Sealed Secrets Controller** - Bitnami sealed-secrets in cluster
- **cert-manager** - For TLS certificate automation
- **nginx-ingress** - Ingress controller

## License

Apache 2.0
