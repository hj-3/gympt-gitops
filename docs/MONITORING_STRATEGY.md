# Monitoring 전략

## 목적

이 문서는 GYMPT 플랫폼의 모니터링 범위, 알람 기준, 대시보드, Alertmanager 라우팅, 운영 확인 절차를 정의한다.

목표는 장애를 빠르게 감지하고, 원인을 좁히며, 자동복구 또는 수동 대응으로 이어지는 흐름을 명확히 만드는 것이다.

## 모니터링 구성 요소

### Prometheus

Kubernetes, 애플리케이션, 인프라 메트릭을 수집한다.

수집 대상:

- Kubernetes node/pod/deployment 상태
- Spring Boot Actuator metrics
- Python service metrics
- JVM metrics
- HPA metrics
- Redis metrics
- SQS metrics
- GPU metrics
- Argo CD sync/health metrics
- Remediation worker metrics

### ServiceMonitor

서비스별 scrape 설정을 관리한다.

현재 GitOps 레포지토리의 주요 위치:

```text
platform/monitoring/servicemonitor-backend-api.yaml
platform/monitoring/servicemonitor-agent-service.yaml
platform/monitoring/servicemonitor-posture-analysis.yaml
platform/monitoring/servicemonitor-workers.yaml
charts/*/templates/servicemonitor.yaml
```

### PrometheusRule

알람 조건을 선언한다.

현재 GitOps 레포지토리의 주요 위치:

```text
platform/monitoring/prometheusrule-backend.yaml
platform/monitoring/prometheusrule-infrastructure.yaml
platform/remediation/alert-rules.yaml
```

### Grafana

서비스와 인프라 상태를 시각화한다.

대시보드 위치:

```text
platform/monitoring/dashboard-api-latency.json
platform/monitoring/dashboard-eks-overview.json
platform/monitoring/dashboard-jvm-metrics.json
platform/monitoring/dashboard-gpu-metrics.json
platform/monitoring/dashboard-redis-metrics.json
platform/monitoring/dashboard-sqs-metrics.json
```

### Alertmanager

Prometheus alert를 Slack, PagerDuty, Email, remediation webhook으로 라우팅한다.

## SLI/SLO 기준

### Backend API

SLI:

- request success rate
- 5xx error rate
- p95 latency
- p99 latency
- JVM heap usage
- DB connection pool usage
- pod restart count

권장 SLO:

```text
availability: 99.9%
5xx error rate: < 1%
p95 latency: < 500ms
p99 latency: < 2s
DB pool usage: < 80%
JVM heap usage: < 85%
```

### Agent Service

SLI:

- request success rate
- Bedrock call success rate
- Bedrock throttling count
- p95 latency
- queue processing latency
- pod restart count

권장 SLO:

```text
5xx error rate: < 1%
Bedrock error rate: < 2%
Bedrock throttling: 지속 5분 이하
p95 latency: < 2s
```

### Posture Analysis Service

SLI:

- inference success rate
- inference latency
- GPU utilization
- GPU memory usage
- pod restart count

권장 SLO:

```text
inference success rate: > 99%
p95 inference latency: 서비스 정책에 따라 정의
GPU utilization: 지속 95% 이상이면 warning
GPU memory usage: 지속 90% 이상이면 critical 후보
```

### Worker / Queue

SLI:

- SQS visible messages
- oldest message age
- DLQ message count
- worker processing success rate
- worker restart count

권장 SLO:

```text
oldest message age: < 5분
DLQ message count: 0
queue backlog: 환경별 threshold 이하
```

## 알람 심각도 기준

### critical

즉시 대응이 필요한 장애 또는 데이터 손실 가능성이 있는 상황이다.

예:

- 5xx error rate가 5분 이상 5% 초과
- DLQ message 발생
- DB connection pool 90% 초과
- pod crash loop
- prod ingress health check 실패

### warning

서비스 영향 가능성이 있으나 즉시 장애로 단정하기 어려운 상황이다.

예:

- p99 latency 2초 초과
- JVM heap 90% 초과
- Redis memory 90% 초과
- SQS backlog 증가
- GPU utilization 95% 초과

### info

운영 참고용 이벤트다.

예:

- deployment completed
- remediation dry-run action
- HPA scale event

## Alertmanager 라우팅 정책

권장 라우팅:

```text
critical
-> PagerDuty
-> Slack #alerts-critical
-> Remediation webhook 대상이면 remediation-worker

warning
-> Slack #alerts-warning
-> Remediation webhook 대상이면 remediation-worker dry-run 또는 제한 실행

info
-> Slack #alerts-info
```

remediation 관련 알림:

```text
auto-remediation action
-> Slack #auto-remediation
```

## 환경별 모니터링 기준

### dev

- 빠른 피드백 중심
- warning 중심 알림
- remediation은 기본 dry-run 권장
- PagerDuty 연결하지 않음

### prod

- critical 알림은 PagerDuty 연동
- warning은 Slack 중심
- 자동복구는 제한적으로 허용
- rollback 계열 액션은 승인 또는 notify-only 권장

## Dashboard 운영 기준

장애 대응 시 dashboard 진입 순서:

1. EKS overview
2. API latency
3. JVM metrics
4. Redis metrics
5. SQS metrics
6. GPU metrics
7. Argo CD sync/health
8. Remediation worker metrics

각 알람의 runbook에는 관련 dashboard 링크를 포함해야 한다.

## 알람 작성 기준

PrometheusRule 작성 시 다음을 포함한다.

- `alert`
- `expr`
- `for`
- `severity`
- `component`
- `summary`
- `description`
- `runbook_url`

예:

```yaml
- alert: BackendHighErrorRate
  expr: |
    (
      sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m]))
      /
      sum(rate(http_server_requests_seconds_count[5m]))
    ) * 100 > 5
  for: 5m
  labels:
    severity: critical
    component: backend-api
  annotations:
    summary: "Backend API has high 5xx error rate"
    description: "Backend API error rate is above threshold"
    runbook_url: "https://runbooks.gympt.com/backend-high-error-rate"
```

## 현재 구체화가 필요한 항목

- dev/prod namespace 기준 통일
- PrometheusRule의 namespace selector를 실제 배포 namespace와 맞추기
- Alertmanager Slack/PagerDuty route 작성
- prod critical alert의 on-call 정책 정의
- dashboard와 alert runbook 연결
- Argo CD sync failure alert 추가
- External Secrets sync failure alert 추가
- certificate expiration alert 추가
- ingress 4xx/5xx 및 target health alert 추가
