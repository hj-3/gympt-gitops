# NetworkPolicy - Zero-Trust Network Security

This directory contains Kubernetes NetworkPolicy resources implementing zero-trust network security for GYMPT platform services.

## Overview

NetworkPolicies control traffic flow between pods and network endpoints. By default, Kubernetes allows all traffic between pods. NetworkPolicies enable a zero-trust security model where all traffic is denied by default and only explicitly allowed connections are permitted.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Zero-Trust Model                        │
├─────────────────────────────────────────────────────────┤
│  1. Default Deny All (baseline)                         │
│  2. Explicit Allow Rules (least privilege)              │
│  3. Namespace Isolation                                  │
│  4. Pod-to-Pod Authentication                            │
└─────────────────────────────────────────────────────────┘

Internet → ALB → Ingress NGINX → Backend API → Agent Service
                      ↓              ↓              ↓
                WebSocket    PostgreSQL/Redis   DynamoDB
                      ↓              ↓              ↓
            Posture Analysis    Workers         AWS Services
```

## NetworkPolicy Files

### Core Policies

1. **default-deny-all.yaml** - Baseline deny-all policy for each namespace
2. **namespace-labels.yaml** - Required namespace labels for NetworkPolicy selectors
3. **backend-api-netpol.yaml** - Backend API service policies
4. **agent-service-netpol.yaml** - AI Agent service policies
5. **posture-analysis-netpol.yaml** - Posture analysis service policies
6. **workers-netpol.yaml** - Generic worker and remediation worker policies

### Network Topology

#### Backend API
- **Ingress**: Ingress controller (port 8080), Prometheus (port 8080)
- **Egress**: DNS, RDS (5432), Redis (6379), AWS HTTPS (443), Agent Service

#### Agent Service
- **Ingress**: Backend API (port 8000), Prometheus (port 8000)
- **Egress**: DNS, Redis (6379), Backend API (8080), AWS Bedrock HTTPS (443)

#### Posture Analysis Service
- **Ingress**: Ingress controller (WebSocket 8002), Backend API, Prometheus
- **Egress**: DNS, Redis (6379), AWS S3/DynamoDB HTTPS (443)

#### Workers
- **Ingress**: Prometheus (port 8000)
- **Egress**: DNS, Redis (6379), K8s API (443), Argo CD, AWS services HTTPS (443)

## Installation

### Prerequisites

- Kubernetes cluster with NetworkPolicy support (CNI plugin: Calico, Cilium, or AWS VPC CNI)
- Namespaces created and labeled
- Services deployed

### Step 1: Label Namespaces

Apply namespace labels for NetworkPolicy selectors:

```bash
kubectl apply -f namespace-labels.yaml
```

Verify labels:

```bash
kubectl get namespaces --show-labels
```

### Step 2: Apply Default Deny-All

Apply baseline deny-all policy to all namespaces:

```bash
kubectl apply -f default-deny-all.yaml
```

**Warning**: This will block all traffic. Services will be unavailable until allow policies are applied.

### Step 3: Apply Service-Specific Policies

Apply NetworkPolicies for each service:

```bash
# Backend API
kubectl apply -f backend-api-netpol.yaml

# Agent Service
kubectl apply -f agent-service-netpol.yaml

# Posture Analysis Service
kubectl apply -f posture-analysis-netpol.yaml

# Workers
kubectl apply -f workers-netpol.yaml
```

### Step 4: Verify Policies

List NetworkPolicies:

```bash
kubectl get networkpolicies -A
```

Describe a specific policy:

```bash
kubectl describe networkpolicy backend-api-netpol -n backend-api
```

## Testing NetworkPolicies

### Test Allowed Traffic

Test that allowed connections work:

```bash
# Test from backend-api to Redis
kubectl exec -n backend-api -it <backend-api-pod> -- \
  nc -zv <redis-endpoint> 6379

# Test from agent-service to backend-api
kubectl exec -n agent-service -it <agent-service-pod> -- \
  curl http://backend-api.backend-api.svc.cluster.local:8080/health
```

### Test Denied Traffic

Verify that unauthorized connections are blocked:

```bash
# Try to connect from agent-service to RDS (should be denied)
kubectl exec -n agent-service -it <agent-service-pod> -- \
  nc -zv <rds-endpoint> 5432
# Expected: Connection refused or timeout

# Try to connect from external namespace to backend-api
kubectl run test-pod --image=busybox -n default -- sleep 3600
kubectl exec -n default -it test-pod -- \
  wget -O- http://backend-api.backend-api.svc.cluster.local:8080/health --timeout=5
# Expected: Connection timeout
```

### Test DNS Resolution

Verify DNS still works (allowed for all pods):

```bash
kubectl exec -n backend-api -it <backend-api-pod> -- \
  nslookup google.com
# Expected: DNS resolution succeeds
```

## Troubleshooting

### Connection Timeout or Refused

If a legitimate connection is being blocked:

1. **Check NetworkPolicy exists**:
```bash
kubectl get networkpolicy -n <namespace>
```

2. **Verify policy selectors match pods**:
```bash
kubectl get pods -n <namespace> --show-labels
kubectl describe networkpolicy <policy-name> -n <namespace>
```

3. **Check namespace labels**:
```bash
kubectl get namespace <namespace> --show-labels
```

4. **View policy details**:
```bash
kubectl get networkpolicy <policy-name> -n <namespace> -o yaml
```

### Debug with tcpdump

If CNI supports it, capture traffic:

```bash
# On the pod
kubectl exec -n backend-api -it <pod> -- tcpdump -i any -nn port 5432

# Check iptables rules (requires privileged access)
kubectl exec -n backend-api -it <pod> -- iptables -L -n -v
```

### Check CNI Plugin

Verify CNI plugin supports NetworkPolicy:

```bash
# Check CNI plugin
kubectl get ds -n kube-system | grep -E 'calico|cilium|aws-node'

# For AWS VPC CNI, ensure Network Policy is enabled
kubectl get daemonset -n kube-system aws-node -o yaml | grep -i network-policy
```

### Temporarily Disable Policy

To temporarily test without NetworkPolicy:

```bash
# Delete specific policy
kubectl delete networkpolicy <policy-name> -n <namespace>

# Or delete all policies in namespace
kubectl delete networkpolicies --all -n <namespace>
```

**Warning**: Re-apply policies after debugging.

## CIDR Ranges

Update these CIDR ranges to match your VPC configuration:

- **VPC CIDR**: `10.0.0.0/16`
- **Private Subnet (DB/Cache)**: `10.0.21.0/24`
- **Public Subnet**: `10.0.1.0/24`
- **EKS Control Plane**: Managed by AWS (within VPC CIDR)

To find your subnet CIDRs:

```bash
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=<vpc-id>" \
  --query 'Subnets[*].[SubnetId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

## Best Practices

### 1. Start with Default Deny

Always apply default deny-all policy first:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: <namespace>
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

### 2. Use Namespace Selectors

Prefer namespace selectors over IP addresses:

```yaml
# Good: Namespace selector
- from:
    - namespaceSelector:
        matchLabels:
          name: monitoring

# Bad: IP CIDR (brittle)
- from:
    - ipBlock:
        cidr: 10.0.10.0/24
```

### 3. Least Privilege

Only allow necessary ports and protocols:

```yaml
# Good: Specific port
ports:
  - protocol: TCP
    port: 8080

# Bad: All ports
# (no ports specified)
```

### 4. Explicit DNS Access

Always allow DNS resolution:

```yaml
egress:
  - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: kube-system
        podSelector:
          matchLabels:
            k8s-app: kube-dns
    ports:
      - protocol: UDP
        port: 53
```

### 5. Block Metadata Service

Prevent access to EC2 metadata service:

```yaml
egress:
  - to:
      - ipBlock:
          cidr: 0.0.0.0/0
          except:
            - 169.254.169.254/32  # EC2 metadata
```

### 6. Document CIDR Blocks

Always comment CIDR blocks:

```yaml
- to:
    - ipBlock:
        cidr: 10.0.21.0/24  # RDS subnet
```

### 7. Test Before Production

Test NetworkPolicies in dev/staging before applying to production:

```bash
# Apply to dev first
kubectl apply -f backend-api-netpol.yaml --dry-run=client

# Verify in dev environment
kubectl apply -f backend-api-netpol.yaml -n backend-api-dev

# Test connectivity
./scripts/test-connectivity.sh backend-api-dev

# Apply to production
kubectl apply -f backend-api-netpol.yaml -n backend-api-prod
```

### 8. Monitor NetworkPolicy Violations

Use Prometheus metrics to track denied connections:

```promql
# NetworkPolicy denies (depends on CNI plugin)
sum(rate(networkpolicy_drop_count_total[5m])) by (namespace, pod)
```

### 9. Version Control

Keep NetworkPolicies in Git with services:

```
gitops/
├── apps/
│   └── backend-api/
│       ├── deployment.yaml
│       └── networkpolicy.yaml
├── platform/
│   └── network-policies/
│       └── default-deny-all.yaml
```

### 10. Regular Audits

Periodically review and update NetworkPolicies:

```bash
# List all policies
kubectl get networkpolicies -A -o wide

# Audit script
./scripts/audit-network-policies.sh
```

## Security Considerations

### 1. Egress to AWS Services

Allow only necessary AWS services:

```yaml
# Allow HTTPS to AWS (S3, DynamoDB, SQS, etc.)
- to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
          - 169.254.169.254/32  # Metadata service
          - 10.0.0.0/8           # Private networks
          - 172.16.0.0/12
          - 192.168.0.0/16
  ports:
    - protocol: TCP
      port: 443
```

### 2. Internal Service Communication

Use DNS names, not IP addresses:

```yaml
# Service-to-service communication
- to:
    - namespaceSelector:
        matchLabels:
          name: backend-api
      podSelector:
        matchLabels:
          app.kubernetes.io/name: backend-api
  ports:
    - protocol: TCP
      port: 8080
```

### 3. Database Access

Restrict database access to specific services:

```yaml
# Only backend-api can access RDS
- to:
    - ipBlock:
        cidr: 10.0.21.0/24  # DB subnet
  ports:
    - protocol: TCP
      port: 5432
```

### 4. Monitoring Access

Allow Prometheus to scrape all services:

```yaml
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            name: monitoring
        podSelector:
          matchLabels:
            app.kubernetes.io/name: prometheus
    ports:
      - protocol: TCP
        port: 8080  # Metrics port
```

## Integration with Service Mesh

If using Istio or Linkerd, NetworkPolicies complement mTLS:

- **NetworkPolicy**: Layer 3/4 firewall (IP, port)
- **Service Mesh**: Layer 7 security (HTTP, gRPC), mTLS, authorization

Both can coexist:

```yaml
# NetworkPolicy blocks at network level
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
...

# Istio AuthorizationPolicy controls at HTTP level
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
...
```

## Monitoring and Alerting

### Prometheus Alerts

Create alerts for NetworkPolicy issues:

```yaml
groups:
  - name: network-policies
    rules:
      - alert: NetworkPolicyDenied
        expr: rate(networkpolicy_drop_count_total[5m]) > 10
        for: 5m
        annotations:
          summary: "High rate of NetworkPolicy denies in {{ $labels.namespace }}"

      - alert: NetworkPolicyMissing
        expr: absent(networkpolicy_info{namespace="backend-api"})
        for: 5m
        annotations:
          summary: "NetworkPolicy missing in backend-api namespace"
```

### Grafana Dashboard

Visualize NetworkPolicy metrics:
- Denied connections per namespace
- Top denied sources
- Policy coverage

## Compliance

NetworkPolicies help meet compliance requirements:

- **PCI DSS**: Network segmentation (Requirement 1.3)
- **HIPAA**: Access controls (§164.312(a)(1))
- **SOC 2**: Network security (CC6.6)
- **ISO 27001**: Network access control (A.13.1)

## References

- [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [NetworkPolicy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes)
- [Calico NetworkPolicy](https://docs.projectcalico.org/security/kubernetes-network-policy)
- [Cilium NetworkPolicy](https://docs.cilium.io/en/stable/policy/)
- [AWS VPC CNI NetworkPolicy](https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy.html)

## Scripts

Create helper scripts for testing:

```bash
# scripts/test-connectivity.sh
#!/bin/bash
# Test connectivity between services

# scripts/audit-network-policies.sh
#!/bin/bash
# Audit NetworkPolicy coverage

# scripts/apply-network-policies.sh
#!/bin/bash
# Apply NetworkPolicies to all namespaces
```
