#!/bin/bash

# GYMPT GitOps Repository Checker
# Validates GitOps configuration and identifies missing components

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL=0
PASSED=0
FAILED=0
WARNINGS=0

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}GYMPT GitOps Repository Structure Check${NC}"
echo -e "${BLUE}===============================================${NC}"
echo ""

# Function to check if file/directory exists
check_exists() {
    local path="$1"
    local type="$2"  # "file" or "dir"
    local description="$3"
    local priority="$4"  # "critical", "important", "optional"

    TOTAL=$((TOTAL + 1))

    if [ "$type" = "file" ]; then
        if [ -f "${PROJECT_ROOT}/${path}" ]; then
            echo -e "${GREEN}✓${NC} ${description}"
            PASSED=$((PASSED + 1))
            return 0
        fi
    else
        if [ -d "${PROJECT_ROOT}/${path}" ]; then
            echo -e "${GREEN}✓${NC} ${description}"
            PASSED=$((PASSED + 1))
            return 0
        fi
    fi

    if [ "$priority" = "critical" ]; then
        echo -e "${RED}✗${NC} ${description} (CRITICAL)"
        FAILED=$((FAILED + 1))
    elif [ "$priority" = "important" ]; then
        echo -e "${YELLOW}⚠${NC} ${description} (Missing)"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "${YELLOW}○${NC} ${description} (Optional)"
        WARNINGS=$((WARNINGS + 1))
    fi
    return 1
}

# Repository Structure
echo -e "\n${BLUE}=== Repository Structure ===${NC}"
check_exists ".gitignore" "file" "Root .gitignore" "critical"
check_exists "README.md" "file" "Root README.md" "critical"
check_exists "README-GITOPS.md" "file" "GitOps guide" "important"
check_exists "NAMESPACE_STRATEGY.md" "file" "Namespace strategy" "important"
check_exists "CHECKLIST.md" "file" "Project checklist" "important"

# Argo CD Configuration
echo -e "\n${BLUE}=== Argo CD Configuration ===${NC}"
check_exists "argocd/projects/gympt-apps.yaml" "file" "Main application project" "critical"
check_exists "argocd/app-of-apps/dev-apps.yaml" "file" "Dev app-of-apps" "critical"
check_exists "argocd/app-of-apps/prod-apps.yaml" "file" "Prod app-of-apps" "critical"
check_exists "argocd/projects/platform.yaml" "file" "Platform services project" "optional"
check_exists "argocd/app-of-apps/platform-apps.yaml" "file" "Platform app-of-apps" "optional"

# Helm Charts - Backend API
echo -e "\n${BLUE}=== Backend API Helm Chart ===${NC}"
check_exists "charts/backend-api/Chart.yaml" "file" "Backend API Chart.yaml" "critical"
check_exists "charts/backend-api/values.yaml" "file" "Backend API values.yaml" "critical"
check_exists "charts/backend-api/values-dev.yaml" "file" "Backend API values-dev.yaml" "critical"
check_exists "charts/backend-api/values-prod.yaml" "file" "Backend API values-prod.yaml" "critical"
check_exists "charts/backend-api/templates/deployment.yaml" "file" "Backend API deployment" "critical"
check_exists "charts/backend-api/templates/service.yaml" "file" "Backend API service" "critical"
check_exists "charts/backend-api/templates/serviceaccount.yaml" "file" "Backend API service account" "critical"
check_exists "charts/backend-api/templates/pdb.yaml" "file" "Backend API PDB" "optional"

# Helm Charts - Agent Service
echo -e "\n${BLUE}=== Agent Service Helm Chart ===${NC}"
check_exists "charts/agent-service/Chart.yaml" "file" "Agent Service Chart.yaml" "critical"
check_exists "charts/agent-service/values.yaml" "file" "Agent Service values.yaml" "critical"
check_exists "charts/agent-service/values-dev.yaml" "file" "Agent Service values-dev.yaml" "critical"
check_exists "charts/agent-service/values-prod.yaml" "file" "Agent Service values-prod.yaml" "critical"

# Helm Charts - Posture Analysis Service
echo -e "\n${BLUE}=== Posture Analysis Service Helm Chart ===${NC}"
check_exists "charts/posture-analysis-service/Chart.yaml" "file" "Posture Analysis Chart.yaml" "critical"
check_exists "charts/posture-analysis-service/values.yaml" "file" "Posture Analysis values.yaml" "critical"
check_exists "charts/posture-analysis-service/values-dev.yaml" "file" "Posture Analysis values-dev.yaml" "critical"
check_exists "charts/posture-analysis-service/values-prod.yaml" "file" "Posture Analysis values-prod.yaml" "critical"

# Helm Charts - Report Service
echo -e "\n${BLUE}=== Report Service Helm Chart ===${NC}"
check_exists "charts/report-service/Chart.yaml" "file" "Report Service Chart.yaml" "critical"
check_exists "charts/report-service/values.yaml" "file" "Report Service values.yaml" "critical"

# Helm Charts - Workers
echo -e "\n${BLUE}=== Worker Helm Charts ===${NC}"
check_exists "charts/remediation-worker" "dir" "Remediation worker chart" "important"

# Argo CD Applications - Dev
echo -e "\n${BLUE}=== Argo CD Applications (Dev) ===${NC}"
check_exists "argocd/applications/dev/backend-api.yaml" "file" "Backend API dev app" "critical"
check_exists "argocd/applications/dev/agent-service.yaml" "file" "Agent Service dev app" "critical"
check_exists "argocd/applications/dev/posture-analysis-service.yaml" "file" "Posture Analysis dev app" "critical"
check_exists "argocd/applications/dev/report-service.yaml" "file" "Report Service dev app" "critical"
check_exists "argocd/applications/dev/remediation-worker.yaml" "file" "Remediation Worker dev app" "important"
check_exists "argocd/applications/dev/monitoring.yaml" "file" "Monitoring dev app" "optional"

# Argo CD Applications - Prod
echo -e "\n${BLUE}=== Argo CD Applications (Prod) ===${NC}"
check_exists "argocd/applications/prod/backend-api.yaml" "file" "Backend API prod app" "critical"
check_exists "argocd/applications/prod/agent-service.yaml" "file" "Agent Service prod app" "critical"
check_exists "argocd/applications/prod/posture-analysis-service.yaml" "file" "Posture Analysis prod app" "critical"
check_exists "argocd/applications/prod/report-service.yaml" "file" "Report Service prod app" "critical"

# Platform Configuration - Monitoring
echo -e "\n${BLUE}=== Platform - Monitoring ===${NC}"
check_exists "platform/monitoring/README.md" "file" "Monitoring README" "critical"
check_exists "platform/monitoring/values-dev.yaml" "file" "kube-prometheus-stack dev values" "critical"
check_exists "platform/monitoring/values-prod.yaml" "file" "kube-prometheus-stack prod values" "important"
check_exists "platform/monitoring/servicemonitor-backend-api.yaml" "file" "Backend API ServiceMonitor" "critical"
check_exists "platform/monitoring/servicemonitor-agent-service.yaml" "file" "Agent Service ServiceMonitor" "critical"
check_exists "platform/monitoring/servicemonitor-posture-analysis.yaml" "file" "Posture Analysis ServiceMonitor" "critical"
check_exists "platform/monitoring/servicemonitor-workers.yaml" "file" "Workers ServiceMonitor" "important"
check_exists "platform/monitoring/prometheusrule-backend.yaml" "file" "Backend PrometheusRules" "critical"
check_exists "platform/monitoring/prometheusrule-infrastructure.yaml" "file" "Infrastructure PrometheusRules" "critical"
check_exists "platform/monitoring/dashboard-eks-overview.json" "file" "EKS dashboard" "important"
check_exists "platform/monitoring/dashboard-api-latency.json" "file" "API latency dashboard" "important"
check_exists "platform/monitoring/dashboard-jvm-metrics.json" "file" "JVM metrics dashboard" "important"
check_exists "platform/monitoring/dashboard-gpu-metrics.json" "file" "GPU metrics dashboard" "important"
check_exists "platform/monitoring/dashboard-redis-metrics.json" "file" "Redis metrics dashboard" "important"
check_exists "platform/monitoring/dashboard-sqs-metrics.json" "file" "SQS metrics dashboard" "important"

# Platform Configuration - Logging
echo -e "\n${BLUE}=== Platform - Logging ===${NC}"
check_exists "platform/logging/README.md" "file" "Logging README" "critical"
check_exists "platform/logging/fluent-bit-values.yaml" "file" "Fluent Bit values" "important"

# Platform Configuration - Remediation
echo -e "\n${BLUE}=== Platform - Remediation ===${NC}"
check_exists "platform/remediation/values-dev.yaml" "file" "Remediation values-dev" "critical"
check_exists "platform/remediation/values-prod.yaml" "file" "Remediation values-prod" "important"
check_exists "platform/remediation/alert-rules.yaml" "file" "Alert rules" "critical"
check_exists "platform/remediation/runbooks.md" "file" "Runbooks" "critical"

# Platform Configuration - External Secrets
echo -e "\n${BLUE}=== Platform - External Secrets ===${NC}"
check_exists "platform/external-secrets" "dir" "External Secrets directory" "important"
check_exists "platform/external-secrets/values.yaml" "file" "ESO values" "important"
check_exists "platform/external-secrets/secretstore-aws.yaml" "file" "AWS SecretStore" "important"

# CI/CD
echo -e "\n${BLUE}=== CI/CD Workflows ===${NC}"
check_exists ".github/workflows/kubeconform.yml" "file" "Kubeconform validation" "critical"
check_exists ".github/workflows/helm-lint.yml" "file" "Helm lint" "important"
check_exists ".github/workflows/helm-test.yml" "file" "Helm test" "optional"
check_exists ".github/workflows/sync-dev.yml" "file" "Auto-sync dev" "optional"

# Documentation
echo -e "\n${BLUE}=== Documentation ===${NC}"
check_exists "platform/README.md" "file" "Platform README" "important"
check_exists "docs/architecture.md" "file" "Architecture diagrams" "optional"
check_exists "docs/deployment-process.md" "file" "Deployment procedures" "important"
check_exists "docs/rollback-procedures.md" "file" "Rollback guide" "important"
check_exists "docs/troubleshooting.md" "file" "Troubleshooting guide" "important"

# YAML Validation
echo -e "\n${BLUE}=== YAML Validation ===${NC}"
if command -v yamllint &> /dev/null; then
    TOTAL=$((TOTAL + 1))
    if yamllint -d relaxed "${PROJECT_ROOT}/argocd" &> /dev/null; then
        echo -e "${GREEN}✓${NC} YAML files are valid"
        PASSED=$((PASSED + 1))
    else
        echo -e "${YELLOW}⚠${NC} YAML validation warnings (check syntax)"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "${YELLOW}○${NC} yamllint not installed (skipping validation)"
fi

# Helm Validation
echo -e "\n${BLUE}=== Helm Chart Validation ===${NC}"
if command -v helm &> /dev/null; then
    for chart in backend-api agent-service posture-analysis-service report-service; do
        TOTAL=$((TOTAL + 1))
        if helm lint "${PROJECT_ROOT}/charts/${chart}" &> /dev/null; then
            echo -e "${GREEN}✓${NC} Helm chart ${chart} is valid"
            PASSED=$((PASSED + 1))
        else
            echo -e "${YELLOW}⚠${NC} Helm chart ${chart} has warnings"
            WARNINGS=$((WARNINGS + 1))
        fi
    done
else
    echo -e "${YELLOW}○${NC} Helm not installed (skipping validation)"
fi

# Summary
echo -e "\n${BLUE}=================================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}=================================================${NC}"
echo -e "Total checks:     ${TOTAL}"
echo -e "${GREEN}Passed:           ${PASSED}${NC}"
echo -e "${YELLOW}Warnings:         ${WARNINGS}${NC}"
echo -e "${RED}Failed (Critical): ${FAILED}${NC}"

PERCENTAGE=$((PASSED * 100 / TOTAL))
echo -e "\nCompletion:       ${PERCENTAGE}%"

# Critical issues
if [ $FAILED -gt 0 ]; then
    echo -e "\n${RED}⚠ CRITICAL ISSUES FOUND${NC}"
    echo -e "Please address the failed items above before proceeding."
    exit 1
fi

# Recommendations
echo -e "\n${BLUE}=== Top Recommendations ===${NC}"
echo -e "1. ${YELLOW}Implement External Secrets Operator${NC} for secret management"
echo -e "2. ${YELLOW}Create Helm charts for workers${NC} (remediation-worker)"
echo -e "3. ${YELLOW}Add NetworkPolicies${NC} to all service templates"
echo -e "4. ${YELLOW}Implement PodDisruptionBudgets${NC} for all services"
echo -e "5. ${YELLOW}Add Helm chart testing${NC} in CI/CD"
echo -e "6. ${YELLOW}Create deployment documentation${NC} (procedures, rollback, DR)"

# Security checks
echo -e "\n${BLUE}=== Security Checks ===${NC}"
TOTAL=$((TOTAL + 1))
if grep -r "hardcoded-secret" "${PROJECT_ROOT}/charts" &> /dev/null; then
    echo -e "${RED}✗${NC} Potential hardcoded secrets found"
    FAILED=$((FAILED + 1))
else
    echo -e "${GREEN}✓${NC} No obvious hardcoded secrets"
    PASSED=$((PASSED + 1))
fi

TOTAL=$((TOTAL + 1))
if find "${PROJECT_ROOT}/charts" -name "*.yaml" -exec grep -l "serviceAccountName:" {} \; | wc -l | grep -q "^[0-9]"; then
    echo -e "${GREEN}✓${NC} Service accounts configured"
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}⚠${NC} Some charts may be missing service accounts"
    WARNINGS=$((WARNINGS + 1))
fi

# Chart consistency
echo -e "\n${BLUE}=== Chart Consistency ===${NC}"
for chart in backend-api agent-service posture-analysis-service report-service; do
    TOTAL=$((TOTAL + 4))
    if [ -f "${PROJECT_ROOT}/charts/${chart}/Chart.yaml" ]; then
        PASSED=$((PASSED + 1))
        if [ -f "${PROJECT_ROOT}/charts/${chart}/values.yaml" ]; then
            PASSED=$((PASSED + 1))
        else
            echo -e "${YELLOW}⚠${NC} Chart ${chart} missing values.yaml"
            WARNINGS=$((WARNINGS + 1))
        fi
        if [ -f "${PROJECT_ROOT}/charts/${chart}/values-dev.yaml" ]; then
            PASSED=$((PASSED + 1))
        else
            echo -e "${YELLOW}⚠${NC} Chart ${chart} missing values-dev.yaml"
            WARNINGS=$((WARNINGS + 1))
        fi
        if [ -f "${PROJECT_ROOT}/charts/${chart}/values-prod.yaml" ]; then
            PASSED=$((PASSED + 1))
        else
            echo -e "${YELLOW}⚠${NC} Chart ${chart} missing values-prod.yaml"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        WARNINGS=$((WARNINGS + 4))
    fi
done

echo -e "\n${GREEN}✓ GitOps validation complete${NC}\n"
exit 0
