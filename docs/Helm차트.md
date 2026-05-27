# Helm 차트 가이드

## 차트 구조

```
backend-api/
├── Chart.yaml              # 차트 메타데이터
├── values.yaml             # 기본값
├── values-dev.yaml         # Dev 환경 설정
├── values-prod.yaml        # Prod 환경 설정
└── templates/
    ├── _helpers.tpl        # 템플릿 헬퍼
    ├── deployment.yaml     # Deployment
    ├── service.yaml        # Service
    ├── serviceaccount.yaml # ServiceAccount
    ├── configmap.yaml      # ConfigMap
    ├── hpa.yaml            # HorizontalPodAutoscaler
    ├── pdb.yaml            # PodDisruptionBudget
    ├── servicemonitor.yaml # Prometheus ServiceMonitor
    └── ingress.yaml        # Ingress
```

## Chart.yaml

```yaml
apiVersion: v2
name: backend-api
description: GYMPT Backend API Service
type: application
version: 1.0.0
appVersion: "1.0.0"
keywords:
  - gympt
  - backend
  - api
maintainers:
  - name: GYMPT DevOps Team
```

## values.yaml (기본값)

```yaml
replicaCount: 2

image:
  repository: YOUR_ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com/gympt/backend-api
  pullPolicy: IfNotPresent
  tag: ""  # Chart appVersion이 기본값

serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: ""  # IRSA ARN
  name: ""

podAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/actuator/prometheus"

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

resources:
  limits:
    cpu: 1000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 1Gi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

pdb:
  enabled: true
  minAvailable: 1
```

## 환경별 Values

### values-dev.yaml
```yaml
replicaCount: 1

image:
  tag: "dev-latest"

resources:
  limits:
    cpu: 500m
    memory: 1Gi
  requests:
    cpu: 250m
    memory: 512Mi

autoscaling:
  enabled: false

pdb:
  enabled: false
```

### values-prod.yaml
```yaml
replicaCount: 3

image:
  tag: "1.0.0"

resources:
  limits:
    cpu: 2000m
    memory: 4Gi
  requests:
    cpu: 1000m
    memory: 2Gi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20

pdb:
  enabled: true
  minAvailable: 2
```

## Helm 명령어

### 차트 검증
```bash
# Lint
helm lint charts/backend-api

# Template 렌더링
helm template backend-api charts/backend-api \
  -f charts/backend-api/values-dev.yaml \
  --namespace backend-api

# Dry-run 설치
helm install backend-api charts/backend-api \
  -f charts/backend-api/values-dev.yaml \
  --namespace backend-api \
  --create-namespace \
  --dry-run
```

### 로컬 테스트
```bash
# 설치
helm install backend-api charts/backend-api \
  -f charts/backend-api/values-dev.yaml \
  --namespace backend-api \
  --create-namespace

# 업그레이드
helm upgrade backend-api charts/backend-api \
  -f charts/backend-api/values-dev.yaml \
  --namespace backend-api

# 삭제
helm uninstall backend-api -n backend-api
```

## 모범 사례

### 1. Values 구조화
- 기본값은 values.yaml에
- 환경별 override는 values-{env}.yaml에
- 민감한 정보는 External Secrets 사용

### 2. 템플릿 헬퍼 활용
```yaml
{{- define "backend-api.fullname" -}}
{{- .Values.fullnameOverride | default .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "backend-api.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "backend-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
```

### 3. 조건부 리소스
```yaml
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
...
{{- end }}
```

### 4. 주석 추가
```yaml
# Backend API 복제본 수
# Dev: 1, Prod: 3
replicaCount: 2
```

## 차트별 특징

### Backend API
- Spring Boot 애플리케이션
- Actuator Health Check
- Prometheus 메트릭
- RDS, Redis 연결

### Agent Service
- Python/FastAPI
- Bedrock 접근 (IRSA)
- 긴 초기화 시간

### Posture Analysis Service
- GPU 필요
- NVIDIA GPU NodeSelector
- 높은 리소스 요구

### Workers
- Celery Workers
- SQS 연동
- 낮은 리소스 요구

## 참고 자료

- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [Helm Template Guide](https://helm.sh/docs/chart_template_guide/)
