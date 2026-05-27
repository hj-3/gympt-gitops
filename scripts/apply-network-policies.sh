#!/bin/bash
# Apply NetworkPolicies to all namespaces
# Usage: ./apply-network-policies.sh [dev|prod]

set -e

ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_ROOT="$(dirname "$SCRIPT_DIR")"
NETPOL_DIR="$GITOPS_ROOT/platform/network-policies"

echo "=================================================="
echo "Applying NetworkPolicies for environment: $ENVIRONMENT"
echo "=================================================="

# Verify kubectl access
if ! kubectl cluster-info &>/dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster"
    echo "Please configure kubectl access first"
    exit 1
fi

# Check if NetworkPolicy CRD exists
if ! kubectl get crd networkpolicies.networking.k8s.io &>/dev/null; then
    echo "Error: NetworkPolicy CRD not found"
    echo "Your CNI plugin may not support NetworkPolicies"
    exit 1
fi

echo ""
echo "Step 1: Applying namespace labels..."
kubectl apply -f "$NETPOL_DIR/namespace-labels.yaml"

echo ""
echo "Step 2: Verifying namespace labels..."
kubectl get namespaces -L name,kubernetes.io/metadata.name,app.kubernetes.io/part-of

echo ""
echo "Step 3: Applying default deny-all policies..."
kubectl apply -f "$NETPOL_DIR/default-deny-all.yaml"

echo ""
echo "WARNING: All traffic is now blocked by default!"
echo "Applying service-specific allow policies in 5 seconds..."
sleep 5

echo ""
echo "Step 4: Applying service-specific NetworkPolicies..."
kubectl apply -f "$NETPOL_DIR/backend-api-netpol.yaml"
kubectl apply -f "$NETPOL_DIR/agent-service-netpol.yaml"
kubectl apply -f "$NETPOL_DIR/posture-analysis-netpol.yaml"
kubectl apply -f "$NETPOL_DIR/workers-netpol.yaml"

echo ""
echo "Step 5: Verifying NetworkPolicies..."
kubectl get networkpolicies -A

echo ""
echo "=================================================="
echo "NetworkPolicies applied successfully!"
echo "=================================================="
echo ""
echo "Next steps:"
echo "1. Test connectivity between services"
echo "2. Verify Prometheus scraping still works"
echo "3. Check application logs for connection errors"
echo ""
echo "To test connectivity, run:"
echo "  ./scripts/test-connectivity.sh"
echo ""
echo "To view NetworkPolicy details:"
echo "  kubectl describe networkpolicy -n <namespace>"
echo ""
echo "To troubleshoot blocked traffic:"
echo "  kubectl logs -n <namespace> <pod> --tail=100"
echo ""
