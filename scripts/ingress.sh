#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

CONTEXT="kind-redis-lab"

# ANSI color codes
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m" # No Color

fail() {
    printf "\n${RED}ERROR: %s${NC}\n" "$1" >&2
    exit 1
}

success() {
    printf "${GREEN}%s${NC}\n" "$1"
}

command -v kubectl >/dev/null 2>&1 \
    || fail "kubectl was not found."

[[ -f "${PROJECT_DIR}/k8s/ingress.yaml" ]] \
    || fail "Missing k8s/ingress.yaml."

kubectl \
    --context="${CONTEXT}" \
    get ingressclass nginx >/dev/null \
    || fail "IngressClass nginx was not found. Install the controller first."
success "IngressClass nginx verified"

kubectl \
    --context="${CONTEXT}" \
    --namespace=ingress-nginx \
    rollout status deployment/ingress-nginx-controller \
    --timeout=300s
success "Ingress controller is ready"

service_type="$(
    kubectl \
        --context="${CONTEXT}" \
        --namespace=default \
        get service python-api \
        -o jsonpath='{.spec.type}'
)"

[[ "${service_type}" == "ClusterIP" ]] \
    || fail "Expected python-api Service type ClusterIP."
success "Service type verified as ClusterIP"

kubectl \
    --context="${CONTEXT}" \
    --namespace=default \
    apply -f "${PROJECT_DIR}/k8s/ingress.yaml"

kubectl \
    --context="${CONTEXT}" \
    --namespace=default \
    get ingress fastapi-ingress

printf "\n${GREEN}Ingress resource applied successfully.${NC}\n"
printf 'Application URL: http://localhost/api/\n'
printf 'Run tests with:\n'
printf 'BASE_URL=http://localhost/api "%s/scripts/test.sh"\n' \
    "${PROJECT_DIR}"
