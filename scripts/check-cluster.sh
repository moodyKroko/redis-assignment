#!/usr/bin/env bash

set -euo pipefail

CLUSTER_NAME="redis-lab"
CONTEXT_NAME="kind-redis-lab"
NODE_NAME="redis-lab-control-plane"

# ANSI color codes
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m" # No Color

check() {
    echo
    echo "==> $1"
}

fail() {
    echo -e "${RED}FAILED: $1${NC}" >&2
    exit 1
}

pass() {
    echo -e "${GREEN}PASS: $1${NC}"
}

echo "========================================"
echo "Stage 3 Kubernetes Verification"
echo "========================================"

# -------------------------------------------
# Check 1: Docker
# -------------------------------------------

check "1/11: Docker Engine"

docker info >/dev/null 2>&1 \
    || fail "Docker is unavailable"

pass "Docker Engine available"

# -------------------------------------------
# Check 2: kind cluster
# -------------------------------------------

check "2/11: kind cluster"

kind get clusters | grep -Fxq "$CLUSTER_NAME" \
    || fail "redis-lab cluster does not exist"

pass "Cluster exists"

# -------------------------------------------
# Check 3: kubectl context
# -------------------------------------------

check "3/11: Kubernetes context"

CURRENT_CONTEXT="$(kubectl config current-context)"

[ "$CURRENT_CONTEXT" = "$CONTEXT_NAME" ] \
    || fail "Incorrect context: $CURRENT_CONTEXT"

pass "Correct context"

# -------------------------------------------
# Check 4: API server
# -------------------------------------------

check "4/11: Kubernetes API"

kubectl get --raw=/readyz >/dev/null \
    || fail "Kubernetes API is not ready"

pass "Kubernetes API ready"

# -------------------------------------------
# Check 5: Node readiness
# -------------------------------------------

check "5/11: Kubernetes node"

kubectl wait \
    --for=condition=Ready \
    "node/${NODE_NAME}" \
    --timeout=120s

pass "Node Ready"

# -------------------------------------------
# Check 6: Node label
# -------------------------------------------

check "6/11: Ingress-ready label"

LABEL="$(
    kubectl get node "$NODE_NAME" \
        -o jsonpath='{.metadata.labels.ingress-ready}'
)"

[ "$LABEL" = "true" ] \
    || fail "Node label is missing"

pass "Node label present"

# -------------------------------------------
# Check 7: Port mappings
# -------------------------------------------

check "7/11: Docker port mappings"

PORTS="$(docker port "$NODE_NAME")"

echo "$PORTS"

grep -Eq '^80/tcp -> .*:80$' <<< "$PORTS" \
    || fail "Host port 80 mapping missing"

grep -Eq '^30080/tcp -> .*:8080$' <<< "$PORTS" \
    || fail "Host port 8080 mapping missing"

pass "Port mappings correct"

# -------------------------------------------
# Check 8: StorageClass
# -------------------------------------------

check "8/11: StorageClass"

kubectl get storageclass standard >/dev/null \
    || fail "StorageClass standard missing"

pass "StorageClass available"

# -------------------------------------------
# Check 9: CoreDNS
# -------------------------------------------

check "9/11: CoreDNS"

kubectl rollout status \
    deployment/coredns \
    -n kube-system \
    --timeout=120s

pass "CoreDNS available"

# -------------------------------------------
# Check 10: Storage provisioner
# -------------------------------------------

check "10/11: Local-path storage provisioner"

kubectl rollout status \
    deployment/local-path-provisioner \
    -n local-path-storage \
    --timeout=120s

pass "Storage provisioner available"

# -------------------------------------------
# Check 11: FastAPI image
# -------------------------------------------

check "11/11: FastAPI image in kind"

docker exec "$NODE_NAME" crictl images \
    | grep -q 'python-api' \
    || fail "FastAPI image missing from kind"

pass "FastAPI image loaded"

# -------------------------------------------
# Final report
# -------------------------------------------

echo
echo "========================================"
echo -e "${GREEN}ALL 11 CHECKS PASSED${NC}"
echo "========================================"

echo
echo "Kubernetes nodes:"
kubectl get nodes

echo
echo "Namespaces:"
kubectl get namespaces

echo
echo "StorageClasses:"
kubectl get storageclass

echo
echo "System Pods:"
kubectl get pods -A

echo
echo "Stage 3 is ready for application deployment."
