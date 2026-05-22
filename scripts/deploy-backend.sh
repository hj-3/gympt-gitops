#!/bin/bash

set -e

ENV=${1:-prod}

echo "🚀 Deploying backend applications for environment: ${ENV}"

kubectl config current-context
echo ""
read -p "Is this the correct cluster? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "❌ Aborted. Please switch to the correct cluster."
  exit 1
fi

kubectl create namespace gympt-${ENV} --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "📦 Applying Argo CD Applications..."

APPS=(
  "backend-api"
  "agent-service"
  "posture-analysis-service"
  "remediation-worker"
)

for APP in "${APPS[@]}"; do
  echo ""
  echo "Deploying ${APP}..."

  # Updated path to match actual directory structure
  APP_FILE="argocd/applications/${ENV}/${APP}.yaml"

  if [ ! -f "${APP_FILE}" ]; then
    echo "  ⚠️  Application file not found: ${APP_FILE}"
    echo "  Creating basic Application manifest..."

    # Create directory if it doesn't exist
    mkdir -p "argocd/applications/${ENV}"

    cat > "${APP_FILE}" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${APP}
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gympt-gitops.git
    targetRevision: main
    path: apps/${ENV}/${APP}
  destination:
    server: https://kubernetes.default.svc
    namespace: gympt-${ENV}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
    echo "  Created: ${APP_FILE}"
  fi

  kubectl apply -f "${APP_FILE}"
  echo "  ✓ ${APP} Application created"
done

echo ""
echo "⏳ Waiting for applications to sync..."
sleep 10

for APP in "${APPS[@]}"; do
  echo "Syncing ${APP}..."
  kubectl -n argocd wait --for=condition=Synced application/${APP} --timeout=300s || true
done

echo ""
echo "📊 Application Status:"
kubectl get applications -n argocd

echo ""
echo "📊 Pod Status:"
kubectl get pods -n gympt-${ENV}

echo ""
echo "✅ Backend deployment initiated!"
echo ""
echo "Monitor deployment:"
echo "  kubectl get applications -n argocd"
echo "  kubectl get pods -n gympt-${ENV} -w"
echo ""
echo "Check Argo CD UI:"
echo "  kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo "  https://localhost:8080"
