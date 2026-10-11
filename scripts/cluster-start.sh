#!/usr/bin/env bash

set -euo pipefail

# -------------------------------------------
# Locate the project root
# -------------------------------------------

PROJECT_ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"

cd "$PROJECT_ROOT"

# -------------------------------------------
# Configuration & Colors
# -------------------------------------------

CLUSTER_NAME="redis-lab"
CONTEXT_NAME="kind-redis-lab"
NODE_NAME="redis-lab-control-plane"

CONFIG_FILE="$PROJECT_ROOT/kind-cluster.yaml"
IMAGE_NAME="python-api:latest"

# ANSI color codes
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# -------------------------------------------
# Helper functions
# -------------------------------------------

log() {
    echo
    echo "==> $1"
}

fail() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

success() {
    echo -e "${GREEN}$1${NC}"
}

# -------------------------------------------
# Check required commands
# -------------------------------------------

log "Checking required commands"

for command_name in docker kind kubectl; do
    command -v "$command_name" >/dev/null 2>&1 \
        || fail "Missing command: $command_name"
done
success "All required commands are available"

# -------------------------------------------
# Check Docker
# -------------------------------------------

log "Checking Docker Engine"

docker info >/dev/null 2>&1 \
    || fail "Docker Engine is unavailable"
success "Docker Engine is available"

# -------------------------------------------
# Check cluster configuration
# -------------------------------------------

log "Checking configuration file"

[ -s "$CONFIG_FILE" ] \
    || fail "Missing or empty file: $CONFIG_FILE"
success "Configuration file is valid"

# -------------------------------------------
# Create or reuse the cluster
# -------------------------------------------

log "Checking kind cluster"

if kind get clusters | grep -Fxq "$CLUSTER_NAME"; then

    success "Cluster already exists."

    docker inspect "$NODE_NAME" >/dev/null 2>&1 \
        || fail "The expected node container is missing"

    PORTS="$(docker port "$NODE_NAME")"

    if ! grep -Eq '^80/tcp -> .*:80$' <<< "$PORTS"; then
        fail "Host port 80 mapping is missing"
    fi

    if ! grep -Eq '^30080/tcp -> .*:8080$' <<< "$PORTS"; then
        fail "Host port 8080 mapping is missing"
    fi

    success "Required port mappings are present."

else

    log "Creating the kind cluster"

    kind create cluster \
        --config "$CONFIG_FILE" \
        --wait 5m
    success "Kind cluster created successfully"

fi

# -------------------------------------------
# Select the Kubernetes context
# -------------------------------------------

log "Selecting Kubernetes context"

kind export kubeconfig --name "$CLUSTER_NAME"

kubectl config use-context "$CONTEXT_NAME"

kubectl config set-context \
    --current \
    --namespace=default
success "Kubernetes context configured"

# -------------------------------------------
# Wait for node readiness
# -------------------------------------------

log "Waiting for the Kubernetes node"

kubectl wait \
    --for=condition=Ready \
    "node/${NODE_NAME}" \
    --timeout=180s
success "Kubernetes node is ready"

# -------------------------------------------
# Check node label
# -------------------------------------------

log "Checking node label"

LABEL_VALUE="$(
    kubectl get node "$NODE_NAME" \
        -o jsonpath='{.metadata.labels.ingress-ready}'
)"

[ "$LABEL_VALUE" = "true" ] \
    || fail "ingress-ready=true label is missing"
success "Node label is present"

# -------------------------------------------
# Check the FastAPI image
# -------------------------------------------

log "Checking the FastAPI image"

if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then

    echo "Building missing Docker image..."

    docker build -t "$IMAGE_NAME" .
    success "Docker image built successfully"
else
    success "Docker image already exists"
fi

# -------------------------------------------
# Load image into kind
# -------------------------------------------

log "Loading the image into kind"

kind load docker-image \
    "$IMAGE_NAME" \
    --name "$CLUSTER_NAME"
success "Image loaded into kind successfully"

# -------------------------------------------
# Display results
# -------------------------------------------

log "Kubernetes nodes"

kubectl get nodes -o wide

log "Cluster information"

kubectl cluster-info

log "Docker port mappings"

docker port "$NODE_NAME"

echo
echo "========================================"
echo -e "${GREEN}Cluster setup completed successfully${NC}"
echo "========================================"
echo
echo "Cluster: redis-lab"
echo "Context: kind-redis-lab"
echo
echo "Stage 4 NodePort URL:"
echo "http://localhost:8080"
echo
echo "Stage 7 Ingress URL:"
echo "http://localhost"
