#!/usr/bin/env bash

set -euo pipefail

CLUSTER_NAME="redis-lab"

# ANSI color codes
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m" # No Color

echo "========================================"
echo "Delete Local Kubernetes Cluster"
echo "========================================"

echo
echo -e "${RED}WARNING:${NC}"
echo "Deleting this cluster removes its Kubernetes"
echo "resources and may permanently destroy"
echo "cluster-local persistent data."
echo

if ! kind get clusters | grep -Fxq "$CLUSTER_NAME"; then
    echo -e "${YELLOW}Cluster redis-lab does not exist.${NC}"
    exit 0
fi

read -r -p "Type DELETE to confirm: " confirmation

if [ "$confirmation" != "DELETE" ]; then
    echo -e "${RED}Deletion cancelled.${NC}"
    exit 0
fi

echo
echo "Deleting cluster..."

kind delete cluster --name "$CLUSTER_NAME"

echo
echo -e "${GREEN}Cluster deleted successfully.${NC}"
echo
echo "To recreate the cluster:"
echo "./scripts/cluster-start.sh"
