# Platform 서비스 가이드

## 개요

Platform 서비스는 애플리케이션을 지원하는 공통 인프라 서비스입니다.

## Monitoring (Prometheus + Grafana)

### 설치

```bash
# Helm 레포지토리 추가
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 설치
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -f platform/monitoring/values-dev.yaml \
  --namespace monitoring \
  --create-namespace
```

### 주요 구성

- **Prometheus**: 메트릭 수집 및 저장
- **Grafana**: 시각화 대시보드
- **Alertmanager**: 알림 라우팅
- **Node Exporter**: 노드 메트릭
- **Kube State Metrics**: Kubernetes 리소스 메트릭

### ServiceMonitor

```bash
# Backend API ServiceMonitor
kubectl apply -f platform/monitoring/servicemonitor-backend-api.yaml
```

### PrometheusRule

```bash
# 알람 규칙
kubectl apply -f platform/monitoring/prometheusrule-backend.yaml
kubectl apply -f platform/monitoring/prometheusrule-infrastructure.yaml
```

### Grafana 대시보드

```bash
# 포트 포워딩
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# 브라우저: http://localhost:3000
# Username: admin
# Password: (values-dev.yaml에 설정)
```

대시보드:
- EKS Overview
- API Latency
- JVM Metrics
- GPU Metrics
- Redis Metrics
- SQS Metrics

## Logging (Fluent Bit + CloudWatch)

### 설치

```bash
# Helm 레포지토리 추가
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update

# 설치
helm install fluent-bit fluent/fluent-bit \
  -f platform/logging/fluent-bit-values.yaml \
  --namespace kube-system
```

### CloudWatch Logs 확인

```bash
# 로그 그룹 목록
aws logs describe-log-groups \
  --log-group-name-prefix /aws/eks/gympt-dev-cluster

# 로그 조회
aws logs tail /aws/eks/gympt-dev-cluster/backend-api --follow
```

### CloudWatch Insights 쿼리

```
# 에러 로그 검색
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100

# 느린 요청
fields @timestamp, method, uri, duration
| filter namespace = "backend-api" and duration > 1000
| sort duration desc
| limit 50
```

## External Secrets Operator

### 설치

```bash
# Helm 레포지토리 추가
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# 설치
helm install external-secrets external-secrets/external-secrets \
  -f platform/external-secrets/values.yaml \
  --namespace external-secrets \
  --create-namespace
```

### SecretStore 생성

```bash
kubectl apply -f platform/external-secrets/secretstore-aws.yaml
```

### ExternalSecret 생성

```bash
kubectl apply -f platform/external-secrets/externalsecret-backend-api.yaml
```

### AWS Secrets Manager 시크릿 생성

```bash
aws secretsmanager create-secret \
  --name gympt/dev/backend-api \
  --secret-string '{
    "database_url": "postgresql://user:pass@host:5432/db",
    "redis_password": "RANDOM_PASSWORD",
    "jwt_secret": "RANDOM_JWT_SECRET"
  }' \
  --region ap-northeast-2
```

## Remediation Worker (자동 복구)

### 설치

```bash
# Namespace 생성
kubectl create namespace workers

# Secret 생성
kubectl create secret generic remediation-worker-secrets \
  --from-literal=slack-webhook-url=https://hooks.slack.com/services/YOUR/WEBHOOK/URL \
  --from-literal=argocd-token=YOUR_ARGOCD_TOKEN \
  -n workers

# 배포
helm install remediation-worker charts/remediation-worker \
  -f platform/remediation/values-dev.yaml \
  --namespace workers
```

### 자동 복구 액션

- **BackendHighErrorRate**: Pod 재시작
- **BackendHighLatency**: HPA 스케일 아웃
- **BackendPodRestarting**: 이전 버전으로 롤백

### Alertmanager 연동

```yaml
alertmanager:
  config:
    route:
      routes:
        - receiver: remediation-worker
          matchers:
            - severity =~ "critical|warning"
          continue: true
    
    receivers:
      - name: remediation-worker
        webhook_configs:
          - url: http://remediation-worker.workers.svc.cluster.local/webhook/alert
            send_resolved: true
```

## NetworkPolicy (Zero-Trust)

### 적용

```bash
# 모든 NetworkPolicy 적용
./scripts/apply-network-policies.sh dev

# 특정 서비스만
kubectl apply -f platform/network-policies/backend-api-netpol.yaml
```

### 연결성 테스트

```bash
# 테스트 실행
./scripts/test-connectivity.sh dev
```

### NetworkPolicy 예시

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-api-netpol
  namespace: backend-api
spec:
  podSelector:
    matchLabels:
      app: backend-api
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - ipBlock:
            cidr: 10.0.21.0/24  # RDS
      ports:
        - protocol: TCP
          port: 5432
```

## 참고 자료

- [Prometheus Operator](https://prometheus-operator.dev/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Fluent Bit](https://docs.fluentbit.io/)
- [External Secrets Operator](https://external-secrets.io/)
- [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
