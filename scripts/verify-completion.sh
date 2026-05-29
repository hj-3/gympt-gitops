#!/bin/bash
# Verify GYMPT GitOps Repository Completion
# Usage: ./verify-completion.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=================================================="
echo "GYMPT GitOps Repository Completion Verification"
echo "=================================================="
echo ""

PASS=0
FAIL=0

# Function to check if file exists
check_file() {
    local file=$1
    local description=$2
    if [ -f "$file" ]; then
        echo "✓ $description"
        ((PASS++))
    else
        echo "✗ $description (MISSING)"
        ((FAIL++))
    fi
}

# Function to check if directory exists
check_dir() {
    local dir=$1
    local description=$2
    if [ -d "$dir" ]; then
        echo "✓ $description"
        ((PASS++))
    else
        echo "✗ $description (MISSING)"
        ((FAIL++))
    fi
}

echo "Checking External Secrets Operator..."
echo "--------------------------------------"
check_file "$GITOPS_ROOT/platform/external-secrets/values.yaml" "ESO Helm values"
check_file "$GITOPS_ROOT/platform/external-secrets/cluster-secret-store.yaml" "ClusterSecretStore"
check_file "$GITOPS_ROOT/platform/external-secrets/external-secret-backend-api.yaml" "Backend API ExternalSecret"
check_file "$GITOPS_ROOT/platform/external-secrets/external-secret-agent-service.yaml" "Agent Service ExternalSecret"
check_file "$GITOPS_ROOT/platform/external-secrets/external-secret-posture-analysis.yaml" "Posture Analysis ExternalSecret"
check_file "$GITOPS_ROOT/platform/external-secrets/external-secret-remediation-worker.yaml" "Remediation Worker ExternalSecret"
check_file "$GITOPS_ROOT/platform/external-secrets/README.md" "ESO Documentation"
echo ""

echo "Checking NetworkPolicies..."
echo "----------------------------"
check_dir "$GITOPS_ROOT/platform/network-policies" "NetworkPolicies directory"
check_file "$GITOPS_ROOT/platform/network-policies/default-deny-all.yaml" "Default deny-all policy"
check_file "$GITOPS_ROOT/platform/network-policies/namespace-labels.yaml" "Namespace labels"
check_file "$GITOPS_ROOT/platform/network-policies/backend-api-netpol.yaml" "Backend API NetworkPolicy"
check_file "$GITOPS_ROOT/platform/network-policies/agent-service-netpol.yaml" "Agent Service NetworkPolicy"
check_file "$GITOPS_ROOT/platform/network-policies/posture-analysis-netpol.yaml" "Posture Analysis NetworkPolicy"
check_file "$GITOPS_ROOT/platform/network-policies/workers-netpol.yaml" "Workers NetworkPolicy"
check_file "$GITOPS_ROOT/platform/network-policies/README.md" "NetworkPolicy Documentation"
echo ""

echo "Checking Documentation..."
echo "--------------------------"
check_file "$GITOPS_ROOT/DEPLOYMENT_COMPLETE.md" "Complete deployment guide"
check_file "$GITOPS_ROOT/COMPLETION_SUMMARY.md" "Completion summary"
check_file "$GITOPS_ROOT/README.md" "Main README"
check_file "$GITOPS_ROOT/README-GITOPS.md" "GitOps README"
echo ""

echo "Checking Scripts..."
echo "--------------------"
check_file "$GITOPS_ROOT/scripts/apply-network-policies.sh" "Apply NetworkPolicies script"
check_file "$GITOPS_ROOT/scripts/test-connectivity.sh" "Test connectivity script"
check_file "$GITOPS_ROOT/scripts/verify-completion.sh" "This verification script"
echo ""

echo "Checking All Helm Charts..."
echo "----------------------------"
check_dir "$GITOPS_ROOT/charts/backend-api" "Backend API chart"
check_dir "$GITOPS_ROOT/charts/agent-service" "Agent Service chart"
check_dir "$GITOPS_ROOT/charts/posture-analysis-service" "Posture Analysis chart"
check_dir "$GITOPS_ROOT/charts/report-service" "Report Service chart"
check_dir "$GITOPS_ROOT/charts/notification-service" "Notification Service chart"
check_dir "$GITOPS_ROOT/charts/remediation-worker" "Remediation Worker chart"
echo ""

echo "Checking Platform Components..."
echo "--------------------------------"
check_dir "$GITOPS_ROOT/platform/cert-manager" "Cert-Manager"
check_dir "$GITOPS_ROOT/platform/external-secrets" "External Secrets"
check_dir "$GITOPS_ROOT/platform/ingress" "Ingress NGINX"
check_dir "$GITOPS_ROOT/platform/logging" "Logging (Fluent Bit)"
check_dir "$GITOPS_ROOT/platform/monitoring" "Monitoring (Prometheus)"
check_dir "$GITOPS_ROOT/platform/remediation" "Remediation Controller"
check_dir "$GITOPS_ROOT/platform/network-policies" "NetworkPolicies"
echo ""

echo "=================================================="
echo "Verification Results"
echo "=================================================="
echo ""
echo "PASSED: $PASS"
echo "FAILED: $FAIL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "✓ GYMPT GitOps Repository is 100% COMPLETE!"
    echo ""
    echo "Next steps:"
    echo "  1. Review DEPLOYMENT_COMPLETE.md for deployment instructions"
    echo "  2. Update AWS account IDs in values files"
    echo "  3. Create secrets in AWS Secrets Manager"
    echo "  4. Deploy to Kubernetes cluster with Argo CD"
    echo ""
    exit 0
else
    echo "✗ Some components are missing. Please review the output above."
    echo ""
    exit 1
fi
