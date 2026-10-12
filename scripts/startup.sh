#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

CLUSTER_NAME="redis-lab"
CONTEXT="kind-${CLUSTER_NAME}"
NAMESPACE="default"
IMAGE="python-api:stage4"

# ANSI color codes
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m" # No Color

log() {
    printf '\n==> %s\n' "$1"
}

fail() {
    printf '\nERROR: %s\n' "$1" >&2
    exit 1
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

    printf '\nStartup failed with exit code %s.\n' "${exit_code}" >&2
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

log "Checking Docker"

docker info >/dev/null 2>&1 \
    || fail "Docker is unavailable. Start Docker Desktop and check WSL integration."

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

log "Checking the Stage 4 NodePort mapping"

port_mapping="$(
    docker inspect \
        --format '{{with index .HostConfig.PortBindings "30080/tcp"}}{{range .}}{{.HostIp}}:{{.HostPort}}{{println}}{{end}}{{end}}' \
        "${CLUSTER_NAME}-control-plane"
)"

[[ "${port_mapping}" == "127.0.0.1:8080" ]] \
    || fail "Expected NodePort mapping 127.0.0.1:8080 -> 30080/tcp. Check Stage 4 kind configuration."

trap diagnostics ERR

log "Waiting for Kubernetes nodes"

k wait \
    --for=condition=Ready \
    nodes \
    --all \
    --timeout=180s

log "Checking the storage class"

k get storageclass standard >/dev/null

log "Building ${IMAGE}"

docker build \
    --tag "${IMAGE}" \
    "${PROJECT_DIR}"

log "Loading the application image into kind"

kind load docker-image \
    "${IMAGE}" \
    --name "${CLUSTER_NAME}"

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

log "Applying the FastAPI Deployment and Service"

k apply -f "${PROJECT_DIR}/k8s/deployment.yaml"
k apply -f "${PROJECT_DIR}/k8s/service.yaml"

k rollout status \
    deployment/python-api \
    --timeout=180s

log "Restarting FastAPI to use the rebuilt image and current environment"

k rollout restart deployment/python-api

k rollout status \
    deployment/python-api \
    --timeout=180s

log "Deployment status"

k get deployments
k get pods
k get services
k get pvc

printf '\nStartup completed successfully.\n'
printf 'FastAPI: http://localhost:8080\n'
printf 'API docs: http://localhost:8080/docs\n'
printf 'Run tests: %s/scripts/test.sh\n' "${PROJECT_DIR}"
