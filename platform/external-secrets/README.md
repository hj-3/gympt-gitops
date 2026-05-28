# External Secrets Operator (ESO)

This directory contains the External Secrets Operator configuration for syncing secrets from AWS Secrets Manager and Parameter Store to Kubernetes Secrets.

## Overview

External Secrets Operator (ESO) is a Kubernetes operator that integrates external secret management systems like AWS Secrets Manager, HashiCorp Vault, Azure Key Vault, and more. It reads information from external APIs and automatically creates Kubernetes secrets.

## Architecture

```
AWS Secrets Manager/Parameter Store
           ↓
    ClusterSecretStore (IRSA authentication)
           ↓
    ExternalSecret (per service)
           ↓
    Kubernetes Secret (auto-created)
           ↓
    Pod (mounts secret)
```

## Installation

### 1. Add Helm Repository

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
```

### 2. Create Namespace

```bash
kubectl create namespace external-secrets-system
```

### 3. Install ESO with Helm

```bash
helm install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets-system \
  -f values.yaml
```

### 4. Verify Installation

```bash
# Check operator pods
kubectl get pods -n external-secrets-system

# Check CRDs
kubectl get crds | grep external-secrets
```

Expected CRDs:
- `clustersecretstores.external-secrets.io`
- `externalsecrets.external-secrets.io`
- `secretstores.external-secrets.io`

## AWS Setup

### 1. Create IAM Policy for ESO

Create an IAM policy with permissions to access Secrets Manager and Parameter Store:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecretVersionIds"
      ],
      "Resource": [
        "arn:aws:secretsmanager:ap-northeast-2:ACCOUNT_ID:secret:gympt/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ],
      "Resource": [
        "arn:aws:ssm:ap-northeast-2:ACCOUNT_ID:parameter/gympt/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt"
      ],
      "Resource": [
        "arn:aws:kms:ap-northeast-2:ACCOUNT_ID:key/*"
      ],
      "Condition": {
        "StringEquals": {
          "kms:ViaService": [
            "secretsmanager.ap-northeast-2.amazonaws.com",
            "ssm.ap-northeast-2.amazonaws.com"
          ]
        }
      }
    }
  ]
}
```

### 2. Create IAM Role for IRSA

```bash
# This should be done in Terraform (already configured)
# Role name: gympt-external-secrets-operator
# Trust relationship with EKS OIDC provider
```

### 3. Update ServiceAccount Annotation

Update `values.yaml` with the actual IAM role ARN:

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT_ID:role/gympt-external-secrets-operator"
```

### 4. Create Secrets in AWS Secrets Manager

Example secret structure for backend-api:

```bash
# Create secret in AWS Secrets Manager
aws secretsmanager create-secret \
  --name gympt/dev/backend-api \
  --description "Backend API secrets for dev environment" \
  --secret-string '{
    "db_username": "gympt_admin",
    "db_password": "REPLACE_WITH_SECURE_PASSWORD",
    "db_host": "gympt-dev-rds.xxxxx.ap-northeast-2.rds.amazonaws.com",
    "db_port": "5432",
    "db_name": "gympt",
    "redis_host": "gympt-dev-redis.xxxxx.cache.amazonaws.com",
    "redis_port": "6379",
    "redis_password": "REPLACE_WITH_SECURE_PASSWORD",
    "jwt_secret": "REPLACE_WITH_SECURE_RANDOM_STRING",
    "aws_access_key_id": "AKIAIOSFODNN7EXAMPLE",
    "aws_secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    "slack_webhook_url": "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX"
  }' \
  --region ap-northeast-2
```

## ClusterSecretStore

Apply the ClusterSecretStore resources:

```bash
kubectl apply -f cluster-secret-store.yaml
```

This creates:
- `aws-secrets-manager` - ClusterSecretStore for AWS Secrets Manager
- `aws-parameter-store` - ClusterSecretStore for AWS Parameter Store

Verify:

```bash
kubectl get clustersecretstore

# Check status
kubectl describe clustersecretstore aws-secrets-manager
```

Expected status: `Valid`

## ExternalSecrets

ExternalSecrets are namespace-scoped resources that reference a ClusterSecretStore and create Kubernetes Secrets.

### Apply ExternalSecrets

```bash
# Backend API
kubectl apply -f external-secret-backend-api.yaml

# Agent Service
kubectl apply -f external-secret-agent-service.yaml

# Posture Analysis Service
kubectl apply -f external-secret-posture-analysis.yaml

# Remediation Worker
kubectl apply -f external-secret-remediation-worker.yaml

# Generic Worker
kubectl apply -f external-secret-generic-worker.yaml
```

### Verify ExternalSecrets

```bash
# List ExternalSecrets
kubectl get externalsecrets -A

# Check status
kubectl describe externalsecret backend-api-secrets -n backend-api

# Verify Kubernetes Secret was created
kubectl get secret backend-api-secrets -n backend-api
```

Expected status: `SecretSynced`

## Secret Rotation

ESO automatically refreshes secrets based on the `refreshInterval` setting (default: 1 hour).

To force immediate sync:

```bash
# Delete the secret, ESO will recreate it
kubectl delete secret backend-api-secrets -n backend-api

# Or annotate the ExternalSecret
kubectl annotate externalsecret backend-api-secrets \
  -n backend-api \
  force-sync="$(date +%s)"
```

## Monitoring

### Check ESO Metrics

ESO exposes Prometheus metrics at `:8080/metrics`:

```bash
# Port-forward to ESO controller
kubectl port-forward -n external-secrets-system \
  svc/external-secrets-webhook 8080:8080

# Check metrics
curl http://localhost:8080/metrics | grep externalsecret
```

Key metrics:
- `externalsecret_sync_calls_total` - Total number of sync calls
- `externalsecret_sync_calls_error` - Number of failed sync calls
- `externalsecret_status_condition` - Status of ExternalSecret resources

### ServiceMonitor

A ServiceMonitor resource is automatically created if `metrics.serviceMonitor.enabled: true` in values.yaml.

Check it:

```bash
kubectl get servicemonitor -n monitoring | grep external-secrets
```

## Troubleshooting

### ExternalSecret Not Syncing

1. Check ExternalSecret status:
```bash
kubectl describe externalsecret <name> -n <namespace>
```

2. Check ESO controller logs:
```bash
kubectl logs -n external-secrets-system \
  -l app.kubernetes.io/name=external-secrets \
  --tail=100
```

3. Verify ClusterSecretStore:
```bash
kubectl get clustersecretstore aws-secrets-manager -o yaml
```

Expected condition: `status.conditions[0].status: "True"`

### IRSA Authentication Issues

1. Verify ServiceAccount annotation:
```bash
kubectl get sa external-secrets-sa -n external-secrets-system -o yaml
```

Should have: `eks.amazonaws.com/role-arn: arn:aws:iam::...`

2. Check IAM role trust policy:
```bash
aws iam get-role --role-name gympt-external-secrets-operator
```

Should have trust relationship with EKS OIDC provider.

3. Verify IAM policy permissions:
```bash
aws iam list-attached-role-policies \
  --role-name gympt-external-secrets-operator
```

### Secret Not Found in AWS

1. Check if secret exists:
```bash
aws secretsmanager describe-secret \
  --secret-id gympt/dev/backend-api \
  --region ap-northeast-2
```

2. Get secret value:
```bash
aws secretsmanager get-secret-value \
  --secret-id gympt/dev/backend-api \
  --region ap-northeast-2
```

3. Verify secret key path in ExternalSecret matches AWS secret name.

### Secret Template Errors

If using `target.template`, verify the template syntax:

```yaml
target:
  template:
    engineVersion: v2  # Required for advanced templating
    data:
      KEY: "{{ .source_key }}"  # Must match keys in AWS secret
```

## Best Practices

### 1. Secret Naming Convention

Use hierarchical naming:
- Format: `gympt/<env>/<service>`
- Example: `gympt/dev/backend-api`, `gympt/prod/backend-api`

### 2. Separate Sensitive and Non-Sensitive

- **Secrets Manager**: Passwords, API keys, tokens (encrypted, rotatable)
- **Parameter Store**: Configuration values, endpoints, non-sensitive settings

### 3. Use Secret Templates

Template secrets to construct complex values:

```yaml
target:
  template:
    data:
      DATABASE_URL: "postgresql://{{ .username }}:{{ .password }}@{{ .host }}:5432/{{ .database }}"
```

### 4. Set Appropriate Refresh Intervals

- **Frequently rotated**: `refreshInterval: 5m`
- **Rarely changed**: `refreshInterval: 1h`
- **Static**: `refreshInterval: 24h`

### 5. Use DeletionPolicy

- `deletionPolicy: Retain` - Keep secret when ExternalSecret is deleted (recommended for production)
- `deletionPolicy: Delete` - Remove secret when ExternalSecret is deleted (dev/test)

### 6. Monitor Secret Sync Status

Set up alerts for `externalsecret_sync_calls_error` metric.

### 7. Test Secret Rotation

Periodically test secret rotation:
1. Update secret in AWS Secrets Manager
2. Wait for `refreshInterval`
3. Verify pods receive updated secret
4. Some apps may need restart

### 8. Use Namespaced SecretStores

For multi-tenant or environment-specific access:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-dev
  namespace: backend-api
spec:
  provider:
    aws:
      service: SecretsManager
      region: ap-northeast-2
      auth:
        jwt:
          serviceAccountRef:
            name: backend-api-sa
            namespace: backend-api
```

## Security Considerations

1. **Least Privilege**: IAM role should only access secrets under `gympt/*` prefix
2. **KMS Encryption**: Use AWS KMS to encrypt secrets at rest
3. **Audit Logging**: Enable CloudTrail logging for Secrets Manager API calls
4. **RBAC**: Restrict access to ExternalSecret and ClusterSecretStore resources
5. **Secret Scanning**: Never commit actual secrets to Git
6. **Rotation**: Implement automated secret rotation for sensitive credentials

## Integration with Helm Charts

In Helm chart templates, reference the secret:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-api
spec:
  template:
    spec:
      containers:
      - name: app
        envFrom:
        - secretRef:
            name: backend-api-secrets  # Created by ExternalSecret
```

## References

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [AWS Secrets Manager Integration](https://external-secrets.io/latest/provider/aws-secrets-manager/)
- [IRSA for EKS](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Helm Chart Values](https://github.com/external-secrets/external-secrets/tree/main/deploy/charts/external-secrets)
