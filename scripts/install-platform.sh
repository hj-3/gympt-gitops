#!/bin/bash

set -e

ENV=${1:-prod}

echo "🚀 Installing platform services for environment: ${ENV}"

kubectl config current-context
echo ""
read -p "Is this the correct cluster? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "❌ Aborted. Please switch to the correct cluster."
  exit 1
fi

echo ""
echo "📦 Step 1/4: Installing Argo CD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Use server-side apply to avoid annotation size limits with large CRDs
echo "  Installing Argo CD manifests (using server-side apply)..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side=true --force-conflicts

echo "  Waiting for Argo CD to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

echo "  ✓ Argo CD installed"
echo "  Admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""

echo ""
echo "📦 Step 2/4: Installing External Secrets Operator..."
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
kubectl create namespace external-secrets-system --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets-system \
  --set installCRDs=true \
  --wait

echo "  ✓ External Secrets Operator installed"

echo ""
echo "📦 Step 3/4: Installing Prometheus & Grafana..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword=admin \
  --wait

echo "  ✓ Prometheus & Grafana installed"

echo ""
echo "📦 Step 4/4: Applying Network Policies..."
if [ -f "platform/network-policies/network-policies.yaml" ]; then
  kubectl apply -f platform/network-policies/network-policies.yaml
  echo "  ✓ Network Policies applied"
else
  echo "  ⚠️  Network policies file not found, skipping"
fi

echo ""
echo "✅ Platform installation complete!"
echo ""
echo "📝 Access information:"
echo ""
echo "Argo CD:"
echo "  kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo "  https://localhost:8080"
echo "  Username: admin"
echo "  Password: [see above]"
echo ""
echo "Grafana:"
echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
echo "  http://localhost:3000"
echo "  Username: admin"
echo "  Password: admin"
echo ""
echo "Next step: Deploy backend applications"
echo "  ./scripts/deploy-backend.sh ${ENV}"
