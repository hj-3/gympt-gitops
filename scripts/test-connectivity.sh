#!/bin/bash
# Test connectivity between services after NetworkPolicy application
# Usage: ./test-connectivity.sh [namespace]

set -e

NAMESPACE=${1:-backend-api}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================="
echo "Testing Connectivity for: $NAMESPACE"
echo "=================================================="

# Verify kubectl access
if ! kubectl cluster-info &>/dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster"
    exit 1
fi

# Get a running pod in the namespace
POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name="$NAMESPACE" \
    --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POD" ]; then
    echo "Error: No running pods found in namespace $NAMESPACE"
    exit 1
fi

echo "Using pod: $POD"
echo ""

# Test DNS resolution
echo "Test 1: DNS Resolution"
echo "------------------------"
if kubectl exec -n "$NAMESPACE" "$POD" -- nslookup google.com &>/dev/null; then
    echo "✓ DNS resolution: PASS"
else
    echo "✗ DNS resolution: FAIL"
fi
echo ""

# Test specific connectivity based on namespace
case $NAMESPACE in
    backend-api)
        echo "Test 2: PostgreSQL RDS Connection"
        echo "-----------------------------------"
        RDS_ENDPOINT=$(kubectl get secret backend-api-secrets -n backend-api \
            -o jsonpath='{.data.db_host}' 2>/dev/null | base64 -d || echo "")
        if [ -n "$RDS_ENDPOINT" ]; then
            if kubectl exec -n "$NAMESPACE" "$POD" -- timeout 5 nc -zv "$RDS_ENDPOINT" 5432 2>&1 | grep -q "open"; then
                echo "✓ PostgreSQL: PASS"
            else
                echo "✗ PostgreSQL: FAIL"
            fi
        else
            echo "⊘ PostgreSQL: SKIPPED (endpoint not found)"
        fi
        echo ""

        echo "Test 3: Redis ElastiCache Connection"
        echo "--------------------------------------"
        REDIS_ENDPOINT=$(kubectl get secret backend-api-secrets -n backend-api \
            -o jsonpath='{.data.redis_host}' 2>/dev/null | base64 -d || echo "")
        if [ -n "$REDIS_ENDPOINT" ]; then
            if kubectl exec -n "$NAMESPACE" "$POD" -- timeout 5 nc -zv "$REDIS_ENDPOINT" 6379 2>&1 | grep -q "open"; then
                echo "✓ Redis: PASS"
            else
                echo "✗ Redis: FAIL"
            fi
        else
            echo "⊘ Redis: SKIPPED (endpoint not found)"
        fi
        echo ""

        echo "Test 4: Agent Service Connection"
        echo "----------------------------------"
        if kubectl exec -n "$NAMESPACE" "$POD" -- timeout 5 nc -zv agent-service.agent-service.svc.cluster.local 8000 2>&1 | grep -q "open"; then
            echo "✓ Agent Service: PASS"
        else
            echo "✗ Agent Service: FAIL"
        fi
        echo ""
        ;;

    agent-service)
        echo "Test 2: Backend API Connection"
        echo "--------------------------------"
        if kubectl exec -n "$NAMESPACE" "$POD" -- timeout 5 nc -zv backend-api.backend-api.svc.cluster.local 8080 2>&1 | grep -q "open"; then
            echo "✓ Backend API: PASS"
        else
            echo "✗ Backend API: FAIL"
        fi
        echo ""

        echo "Test 3: Redis Connection"
        echo "-------------------------"
        REDIS_ENDPOINT=$(kubectl get secret agent-service-secrets -n agent-service \
            -o jsonpath='{.data.redis_host}' 2>/dev/null | base64 -d || echo "")
        if [ -n "$REDIS_ENDPOINT" ]; then
            if kubectl exec -n "$NAMESPACE" "$POD" -- timeout 5 nc -zv "$REDIS_ENDPOINT" 6379 2>&1 | grep -q "open"; then
                echo "✓ Redis: PASS"
            else
                echo "✗ Redis: FAIL"
            fi
        else
            echo "⊘ Redis: SKIPPED (endpoint not found)"
        fi
        echo ""
        ;;

    posture-analysis)
        echo "Test 2: Redis Connection"
        echo "-------------------------"
        REDIS_ENDPOINT=$(kubectl get secret posture-analysis-secrets -n posture-analysis \
            -o jsonpath='{.data.redis_host}' 2>/dev/null | base64 -d || echo "")
        if [ -n "$REDIS_ENDPOINT" ]; then
            if kubectl exec -n "$NAMESPACE" "$POD" -- timeout 5 nc -zv "$REDIS_ENDPOINT" 6379 2>&1 | grep -q "open"; then
                echo "✓ Redis: PASS"
            else
                echo "✗ Redis: FAIL"
            fi
        else
            echo "⊘ Redis: SKIPPED (endpoint not found)"
        fi
        echo ""
        ;;

    workers)
        echo "Test 2: Kubernetes API Connection"
        echo "-----------------------------------"
        if kubectl exec -n "$NAMESPACE" "$POD" -- timeout 5 nc -zv kubernetes.default.svc.cluster.local 443 2>&1 | grep -q "open"; then
            echo "✓ Kubernetes API: PASS"
        else
            echo "✗ Kubernetes API: FAIL"
        fi
        echo ""

        echo "Test 3: Argo CD Connection"
        echo "---------------------------"
        if kubectl exec -n "$NAMESPACE" "$POD" -- timeout 5 nc -zv argocd-server.argocd.svc.cluster.local 80 2>&1 | grep -q "open"; then
            echo "✓ Argo CD: PASS"
        else
            echo "✗ Argo CD: FAIL"
        fi
        echo ""
        ;;
esac

# Test HTTPS to AWS (common for all services)
echo "Test: HTTPS to AWS Services"
echo "----------------------------"
if kubectl exec -n "$NAMESPACE" "$POD" -- timeout 10 curl -s -o /dev/null -w "%{http_code}" https://s3.amazonaws.com 2>&1 | grep -q "403\|200"; then
    echo "✓ AWS S3: PASS"
else
    echo "✗ AWS S3: FAIL"
fi
echo ""

# Test that metadata service is blocked
echo "Test: EC2 Metadata Service (should be blocked)"
echo "------------------------------------------------"
if kubectl exec -n "$NAMESPACE" "$POD" -- timeout 5 curl -s http://169.254.169.254/latest/meta-data/ 2>&1 | grep -q "timed out"; then
    echo "✓ Metadata blocked: PASS"
else
    echo "✗ Metadata blocked: FAIL (security risk!)"
fi
echo ""

echo "=================================================="
echo "Connectivity Test Complete"
echo "=================================================="
echo ""
echo "If any tests failed, check:"
echo "  1. kubectl describe networkpolicy -n $NAMESPACE"
echo "  2. kubectl logs -n $NAMESPACE $POD --tail=100"
echo "  3. kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
echo ""
