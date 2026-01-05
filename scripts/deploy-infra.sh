#!/bin/bash
#
# deploy-infra.sh - Deploy StackEye infrastructure components
#
# Usage:
#   ./scripts/deploy-infra.sh <environment> <cluster> [component]
#
# Examples:
#   ./scripts/deploy-infra.sh dev onprem           # Deploy all infra to dev on-prem
#   ./scripts/deploy-infra.sh dev onprem cnpg      # Deploy only CNPG to dev
#   ./scripts/deploy-infra.sh dev nyc3 tailscale   # Deploy Tailscale to NYC3
#   ./scripts/deploy-infra.sh prd onprem all       # Deploy all to production
#
# Environments: dev, stg, prd
# Clusters: onprem, nyc3, sfo3
# Components: cnpg, valkey, valkey-regional, monitoring, tailscale, secrets, all
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/../infrastructure"

# Default values
ENV="${1:-}"
CLUSTER="${2:-}"
COMPONENT="${3:-all}"

# Kubeconfig paths (adjust as needed for your setup)
KUBECONFIG_ONPREM="${KUBECONFIG_ONPREM:-$HOME/.kube/config}"
KUBECONFIG_NYC3="${KUBECONFIG_NYC3:-$HOME/.kube/mattox/stackeye-nyc3}"
KUBECONFIG_SFO3="${KUBECONFIG_SFO3:-$HOME/.kube/mattox/stackeye-sfo3}"

usage() {
    echo "Usage: $0 <environment> <cluster> [component]"
    echo ""
    echo "Arguments:"
    echo "  environment   Target environment: dev, stg, prd"
    echo "  cluster       Target cluster: onprem, nyc3, sfo3"
    echo "  component     Component to deploy (optional, default: all)"
    echo "                Options: cnpg, valkey, valkey-regional, monitoring, tailscale, secrets, all"
    echo ""
    echo "Examples:"
    echo "  $0 dev onprem              # Deploy all infra to dev on-prem"
    echo "  $0 dev onprem cnpg         # Deploy only CNPG to dev"
    echo "  $0 dev nyc3 tailscale      # Deploy Tailscale to NYC3"
    echo "  $0 prd onprem all          # Deploy all to production"
    echo ""
    echo "Environment Variables:"
    echo "  KUBECONFIG_ONPREM   Path to on-prem kubeconfig (default: ~/.kube/config)"
    echo "  KUBECONFIG_NYC3     Path to NYC3 kubeconfig (default: ~/.kube/mattox/stackeye-nyc3)"
    echo "  KUBECONFIG_SFO3     Path to SFO3 kubeconfig (default: ~/.kube/mattox/stackeye-sfo3)"
    echo "  DRY_RUN             Set to 'true' to show commands without executing"
    exit 1
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate inputs
validate_inputs() {
    if [[ -z "$ENV" ]] || [[ -z "$CLUSTER" ]]; then
        log_error "Missing required arguments"
        usage
    fi

    case "$ENV" in
        dev|stg|prd) ;;
        *)
            log_error "Invalid environment: $ENV (must be dev, stg, or prd)"
            exit 1
            ;;
    esac

    case "$CLUSTER" in
        onprem|nyc3|sfo3) ;;
        *)
            log_error "Invalid cluster: $CLUSTER (must be onprem, nyc3, or sfo3)"
            exit 1
            ;;
    esac

    case "$COMPONENT" in
        cnpg|valkey|valkey-regional|monitoring|tailscale|secrets|all) ;;
        *)
            log_error "Invalid component: $COMPONENT"
            exit 1
            ;;
    esac
}

# Set kubeconfig based on cluster
set_kubeconfig() {
    case "$CLUSTER" in
        onprem)
            export KUBECONFIG="$KUBECONFIG_ONPREM"
            ;;
        nyc3)
            export KUBECONFIG="$KUBECONFIG_NYC3"
            ;;
        sfo3)
            export KUBECONFIG="$KUBECONFIG_SFO3"
            ;;
    esac

    if [[ ! -f "$KUBECONFIG" ]]; then
        log_error "Kubeconfig not found: $KUBECONFIG"
        exit 1
    fi

    log_info "Using kubeconfig: $KUBECONFIG"
}

# Execute kubectl with optional dry-run
kube_apply() {
    local path="$1"
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] kubectl apply -f $path"
    else
        kubectl apply -f "$path"
    fi
}

# Deploy CloudNativePG (on-prem only)
deploy_cnpg() {
    if [[ "$CLUSTER" != "onprem" ]]; then
        log_warn "CNPG is only deployed to on-prem cluster, skipping for $CLUSTER"
        return
    fi

    local cnpg_dir="${INFRA_DIR}/cnpg/${ENV}"
    if [[ ! -d "$cnpg_dir" ]]; then
        log_error "CNPG directory not found: $cnpg_dir"
        exit 1
    fi

    log_info "Deploying CloudNativePG to ${ENV}..."

    # Apply base resources first (namespaces)
    if [[ -d "${INFRA_DIR}/cnpg/base" ]]; then
        log_info "Applying CNPG base resources..."
        kube_apply "${INFRA_DIR}/cnpg/base/"
    fi

    # Apply environment-specific resources
    log_info "Applying CNPG ${ENV} resources..."
    kube_apply "$cnpg_dir/"

    log_success "CloudNativePG deployed to ${ENV}"
}

# Deploy Valkey (on-prem only)
deploy_valkey() {
    if [[ "$CLUSTER" != "onprem" ]]; then
        log_warn "Valkey is only deployed to on-prem cluster, skipping for $CLUSTER"
        return
    fi

    local valkey_dir="${INFRA_DIR}/valkey/${ENV}"
    if [[ ! -d "$valkey_dir" ]]; then
        log_error "Valkey directory not found: $valkey_dir"
        exit 1
    fi

    log_info "Deploying Valkey to ${ENV}..."
    kube_apply "$valkey_dir/"
    log_success "Valkey deployed to ${ENV}"
}

# Deploy Valkey operator to regional clusters
deploy_valkey_operator() {
    if [[ "$CLUSTER" == "onprem" ]]; then
        log_warn "Valkey operator is only deployed to regional clusters, skipping for on-prem"
        return
    fi

    local operator_dir="${INFRA_DIR}/valkey/regional/base/operator"
    if [[ ! -d "$operator_dir" ]]; then
        log_error "Valkey operator directory not found: $operator_dir"
        exit 1
    fi

    log_info "Deploying Valkey operator to ${CLUSTER}..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] kubectl apply -k $operator_dir/"
    else
        kubectl apply -k "$operator_dir/"
    fi

    # Wait for operator to be ready
    log_info "Waiting for Valkey operator to be ready..."
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        kubectl wait --for=condition=available --timeout=120s \
            deployment/valkey-operator-controller-manager \
            -n valkey-operator-system || log_warn "Operator may not be ready yet"
    fi

    log_success "Valkey operator deployed to ${CLUSTER}"
}

# Deploy regional Valkey instance (DOKS clusters only)
deploy_valkey_regional() {
    if [[ "$CLUSTER" == "onprem" ]]; then
        log_warn "Regional Valkey is only deployed to DOKS clusters, skipping for on-prem"
        return
    fi

    local regional_dir="${INFRA_DIR}/valkey/regional/${CLUSTER}"
    if [[ ! -d "$regional_dir" ]]; then
        log_error "Regional Valkey directory not found: $regional_dir"
        exit 1
    fi

    # Ensure operator is installed first
    deploy_valkey_operator

    log_info "Deploying regional Valkey to ${CLUSTER}..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] kubectl apply -k $regional_dir/"
    else
        kubectl apply -k "$regional_dir/"
    fi

    log_success "Regional Valkey deployed to ${CLUSTER}"
}

# Deploy Monitoring stack (on-prem only)
deploy_monitoring() {
    if [[ "$CLUSTER" != "onprem" ]]; then
        log_warn "Monitoring is only deployed to on-prem cluster, skipping for $CLUSTER"
        return
    fi

    local monitoring_dir="${INFRA_DIR}/monitoring"
    if [[ ! -d "$monitoring_dir" ]]; then
        log_error "Monitoring directory not found: $monitoring_dir"
        exit 1
    fi

    log_info "Deploying Monitoring stack..."

    # Apply in order: base, prometheus, grafana
    if [[ -d "${monitoring_dir}/base" ]]; then
        log_info "Applying monitoring base resources..."
        kube_apply "${monitoring_dir}/base/"
    fi

    if [[ -d "${monitoring_dir}/prometheus" ]]; then
        log_info "Applying Prometheus resources..."
        kube_apply "${monitoring_dir}/prometheus/"
    fi

    if [[ -d "${monitoring_dir}/grafana" ]]; then
        log_info "Applying Grafana resources..."
        kube_apply "${monitoring_dir}/grafana/"
    fi

    log_success "Monitoring stack deployed"
}

# Deploy Tailscale connectors (regional clusters only)
deploy_tailscale() {
    if [[ "$CLUSTER" == "onprem" ]]; then
        log_warn "Tailscale connectors are only deployed to regional clusters, skipping for on-prem"
        return
    fi

    local tailscale_dir="${INFRA_DIR}/tailscale/${CLUSTER}"
    if [[ ! -d "$tailscale_dir" ]]; then
        log_error "Tailscale directory not found: $tailscale_dir"
        exit 1
    fi

    log_info "Deploying Tailscale connector to ${CLUSTER}..."
    kube_apply "$tailscale_dir/"
    log_success "Tailscale connector deployed to ${CLUSTER}"
}

# Deploy sealed secrets
deploy_secrets() {
    local secrets_dir=""

    case "$CLUSTER" in
        onprem)
            secrets_dir="${INFRA_DIR}/secrets/a1-ops-prd"
            ;;
        nyc3)
            secrets_dir="${INFRA_DIR}/secrets/stackeye-nyc3"
            ;;
        sfo3)
            secrets_dir="${INFRA_DIR}/secrets/stackeye-sfo3"
            ;;
    esac

    if [[ ! -d "$secrets_dir" ]]; then
        log_error "Secrets directory not found: $secrets_dir"
        exit 1
    fi

    log_info "Deploying secrets for ${CLUSTER} ${ENV}..."

    # Find and apply secrets for this environment
    local secret_files
    secret_files=$(find "$secrets_dir" -name "*-${ENV}.yaml" -type f 2>/dev/null || true)

    if [[ -z "$secret_files" ]]; then
        log_warn "No secrets found for ${ENV} in ${secrets_dir}"
        return
    fi

    for secret_file in $secret_files; do
        log_info "Applying $(basename "$secret_file")..."
        kube_apply "$secret_file"
    done

    log_success "Secrets deployed for ${CLUSTER} ${ENV}"
}

# Deploy all components
deploy_all() {
    log_info "Deploying all infrastructure components to ${ENV} on ${CLUSTER}..."

    if [[ "$CLUSTER" == "onprem" ]]; then
        deploy_cnpg
        deploy_valkey
        deploy_monitoring
        deploy_secrets
    else
        deploy_valkey_regional
        deploy_tailscale
        deploy_secrets
    fi

    log_success "All infrastructure components deployed to ${ENV} on ${CLUSTER}"
}

# Main
main() {
    echo "========================================"
    echo "  StackEye Infrastructure Deployment"
    echo "========================================"
    echo ""

    validate_inputs
    set_kubeconfig

    log_info "Environment: ${ENV}"
    log_info "Cluster: ${CLUSTER}"
    log_info "Component: ${COMPONENT}"
    echo ""

    case "$COMPONENT" in
        cnpg)
            deploy_cnpg
            ;;
        valkey)
            deploy_valkey
            ;;
        valkey-regional)
            deploy_valkey_regional
            ;;
        monitoring)
            deploy_monitoring
            ;;
        tailscale)
            deploy_tailscale
            ;;
        secrets)
            deploy_secrets
            ;;
        all)
            deploy_all
            ;;
    esac

    echo ""
    log_success "Deployment complete!"
}

main "$@"
