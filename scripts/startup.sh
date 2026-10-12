#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

CLUSTER_NAME="redis-lab"
CONTEXT="kind-${CLUSTER_NAME}"
NAMESPACE="default"
IMAGE="python-api:latest"

# ANSI color codes
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m" # No Color

log() {
    printf '\n==> %s\n' "$1"
}

fail() {
    printf "\n${RED}ERROR: %s${NC}\n" "$1" >&2
    exit 1
}

success() {
    printf "${GREEN}%s${NC}\n" "$1"
}

k() {
    kubectl \
        --context="${CONTEXT}" \
        --namespace="${NAMESPACE}" \
        "$@"
}

diagnostics() {
    local exit_code=$?

    trap - ERR

    printf "\n${RED}Startup failed with exit code %s.${NC}\n" "${exit_code}" >&2
    printf 'Current Kubernetes diagnostics:\n' >&2

    k get pods -o wide || true
    k get pvc || true

    k logs deployment/redis --tail=50 || true
    k logs deployment/python-api --tail=50 || true

    k get events \
        --sort-by=.metadata.creationTimestamp || true

    exit "${exit_code}"
}

log "Checking required commands"

for command in docker kind kubectl; do
    command -v "${command}" >/dev/null 2>&1 \
        || fail "Required command not found: ${command}"
done
success "All required commands are available"

log "Checking Docker"

docker info >/dev/null 2>&1 \
    || fail "Docker is unavailable. Start Docker Desktop and check WSL integration."
success "Docker is available"

log "Checking project files"

required_files=(
    "app.py"
    "requirements.txt"
    "Dockerfile"
    "k8s/redis-configmap.yaml"
    "k8s/redis-secret.yaml"
    "k8s/redis-pvc.yaml"
    "k8s/redis-service.yaml"
    "k8s/redis-deployments.yaml"
    "k8s/deployment.yaml"
    "k8s/service.yaml"
)

for file in "${required_files[@]}"; do
    [[ -f "${PROJECT_DIR}/${file}" ]] \
        || fail "Missing file: ${PROJECT_DIR}/${file}"
done
success "All required project files are present"

log "Checking the kind cluster"

clusters="$(kind get clusters)"

cluster_found=false

while IFS= read -r cluster; do
    if [[ "${cluster}" == "${CLUSTER_NAME}" ]]; then
        cluster_found=true
        break
    fi
done <<< "${clusters}"

[[ "${cluster_found}" == true ]] \
    || fail "Cluster '${CLUSTER_NAME}' was not found. Complete Stage 4 cluster setup first."

kubectl config get-contexts "${CONTEXT}" >/dev/null 2>&1 \
    || fail "kubectl context '${CONTEXT}' was not found."
success "Kind cluster and context verified"

trap diagnostics ERR

log "Waiting for Kubernetes nodes"

k wait \
    --for=condition=Ready \
    nodes \
    --all \
    --timeout=180s
success "Kubernetes nodes are ready"

log "Checking the storage class"

k get storageclass standard >/dev/null
success "Storage class verified"

log "Building ${IMAGE}"

docker build \
    --tag "${IMAGE}" \
    "${PROJECT_DIR}"
success "Docker image built successfully"

log "Loading the application image into kind"

kind load docker-image \
    "${IMAGE}" \
    --name "${CLUSTER_NAME}"
success "Image loaded into kind successfully"

log "Applying Redis configuration, storage, and Service"

k apply -f "${PROJECT_DIR}/k8s/redis-configmap.yaml"
k apply -f "${PROJECT_DIR}/k8s/redis-secret.yaml"
k apply -f "${PROJECT_DIR}/k8s/redis-pvc.yaml"
k apply -f "${PROJECT_DIR}/k8s/redis-service.yaml"

log "Applying the Redis Deployment"

k apply -f "${PROJECT_DIR}/k8s/redis-deployments.yaml"

k rollout status \
    deployment/redis \
    --timeout=180s

log "Restarting Redis to load the current Secret"

k rollout restart deployment/redis

k rollout status \
    deployment/redis \
    --timeout=180s

log "Checking Redis authentication and connectivity"

k exec deployment/redis -- \
    sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli ping' \
    | {
        IFS= read -r reply
        [[ "${reply}" == "PONG" ]]
    }
success "Redis is running and authenticated"

log "Applying the FastAPI Deployment and Service"

k apply -f "${PROJECT_DIR}/k8s/deployment.yaml"
k apply -f "${PROJECT_DIR}/k8s/service.yaml"

service_type="$(k get service python-api -o jsonpath='{.spec.type}')"

[[ "${service_type}" == "ClusterIP" ]] \
    || fail "Expected python-api Service type ClusterIP. Check k8s/service.yaml."

k rollout status \
    deployment/python-api \
    --timeout=180s

log "Restarting FastAPI to use the rebuilt image and current environment"

k rollout restart deployment/python-api

k rollout status \
    deployment/python-api \
    --timeout=180s
success "FastAPI deployment rolled out successfully"

log "Deployment status"

k get deployments
k get pods
k get services
k get pvc

printf "\n${GREEN}Startup completed successfully.${NC}\n"
printf '\nIn Terminal A, start port-forwarding:\n'
printf 'kubectl --context=%s --namespace=%s port-forward --address=127.0.0.1 service/python-api 18080:80\n' \
    "${CONTEXT}" "${NAMESPACE}"

printf '\nIn Terminal B, run the tests:\n'
printf 'BASE_URL=http://localhost:18080 "%s/scripts/test.sh"\n' \
    "${PROJECT_DIR}"

printf '\nAPI docs: http://localhost:18080/docs\n'
