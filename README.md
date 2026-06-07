# GYMPT GitOps

> GYMPT 플랫폼을 위한 Kubernetes 매니페스트 및 Helm 차트

[![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-blue)](https://argo-cd.readthedocs.io/)
[![Helm](https://img.shields.io/badge/Helm-3.12+-0F1689)](https://helm.sh/)

---

## 📋 개요

GYMPT 플랫폼을 위한 모든 Kubernetes 매니페스트, Helm 차트, ArgoCD 애플리케이션이 포함된 GitOps 저장소입니다.

### 저장소 구조

```
gympt-gitops/
├── argocd/
│   ├── projects/           # ArgoCD 프로젝트
│   └── applications/       # ArgoCD 애플리케이션 정의
│       ├── platform/       # 플랫폼 서비스 (모니터링 등)
│       └── *.yaml          # App-of-apps 패턴
│
├── charts/                 # 애플리케이션용 Helm 차트
│   ├── backend-api/
│   ├── agent-service/
│   ├── posture-analysis-service/
│   ├── report-service/
│   ├── kvs-consumer-service/
│   └── remediation-worker/
│
├── platform/               # 플랫폼 설정
│   ├── karpenter/         # Karpenter NodePools
│   └── monitoring/        # Prometheus, Grafana 설정
│
└── docs/                  # 문서
```

---

## 🚀 빠른 시작

### 사전 요구사항

- EKS 클러스터 배포 완료 (gympt-infra 통해)
- kubectl 설정 완료
- ArgoCD 설치 완료

### 애플리케이션 배포

```bash
# ArgoCD 설치 (아직 설치하지 않은 경우)
../scripts/bootstrap-argocd.sh

# 모든 애플리케이션 적용
kubectl apply -f argocd/applications/gympt-prod-apps.yaml
```

---

## 📦 애플리케이션

### 백엔드 서비스

| 서비스 | 차트 | 설명 |
|---------|-------|-------------|
| **backend-api** | `charts/backend-api` | 메인 API (Spring Boot) |
| **agent-service** | `charts/agent-service` | AI 에이전트 (AWS Bedrock) |
| **posture-analysis-service** | `charts/posture-analysis-service` | 자세 분석 (MediaPipe + GPU) |
| **report-service** | `charts/report-service` | PDF 리포트 생성 |
| **kvs-consumer-service** | `charts/kvs-consumer-service` | Kinesis Video Stream 컨슈머 |
| **remediation-worker** | `charts/remediation-worker` | 백그라운드 작업 워커 |

### 플랫폼 서비스

| 서비스 | 위치 | 설명 |
|---------|----------|-------------|
| **모니터링 스택** | `argocd/applications/platform/monitoring.yaml` | Prometheus + Grafana |
| **External Secrets** | `argocd/applications/platform/external-secrets.yaml` | AWS Secrets Manager 통합 |

---

## 🔄 GitOps 워크플로우

```
1. 개발자가 gympt-app에 코드 커밋
   ↓
2. CI/CD가 Docker 이미지 빌드 및 ECR에 푸시
   ↓
3. CI/CD가 gympt-gitops main 브랜치의 이미지 태그를 직접 업데이트
   ↓
4. ArgoCD가 Git 변경사항 감지
   ↓
5. ArgoCD가 EKS에 자동 배포
```

`gympt-app`의 서비스별 CI workflow는 `charts/<service>/values-dev.yaml` 또는 `values-prod.yaml`의 `.image.tag`를 갱신한 뒤 PR을 만들지 않고 `main`에 직접 커밋합니다. `main` 브랜치 direct push가 막혀 있으면 `GITOPS_PAT`에 bypass 권한을 부여하거나 branch protection을 조정해야 합니다.

---

## 📝 애플리케이션 업데이트

### 이미지 태그 업데이트

일반 배포는 `gympt-app` CI/CD가 자동으로 처리합니다. 수동으로 태그를 바꿔야 할 때만 아래 절차를 사용합니다.

```bash
# values 파일에서 이미지 태그 업데이트
cd charts/backend-api
sed -i 's/tag: .*/tag: v2.0.0/' values-prod.yaml

# 커밋 및 푸시
git add .
git commit -m "Update backend-api to v2.0.0"
git push

# ArgoCD가 자동으로 동기화
```

### 수동 동기화

```bash
# CLI를 통한 동기화
argocd app sync backend-api-prod

# 또는 UI를 통해
open https://argocd.gympt.com
```

---

## 🎯 환경별 Values

각 차트에는 환경별 values가 있습니다:

```
charts/backend-api/
├── Chart.yaml
├── templates/
├── values.yaml           # 기본값
├── values-dev.yaml       # 개발 환경 오버라이드
└── values-prod.yaml      # 프로덕션 환경 오버라이드
```

---

## 🔐 비밀 관리

### External Secrets Operator 사용

```yaml
# 예시: ExternalSecret
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: backend-api-secrets
spec:
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: backend-api-secrets
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: gympt/prod/db-password
```

---

## 📊 모니터링

### Grafana 접근

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
open http://localhost:3000
# admin / [secret의 비밀번호]
```

### Prometheus 접근

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-stack-prometheus 9090:9090
open http://localhost:9090
```

### Prometheus 스토리지

Prometheus는 50Gi PVC를 사용하며, EKS 기본 StorageClass인 `gp2`를 명시합니다. `storageClassName`이 없으면 PVC가 `Pending` 상태로 남고 Prometheus pod가 뜨지 않아 모든 알람 평가가 중단됩니다.

확인:

```bash
kubectl -n monitoring get pod prometheus-kube-prometheus-stack-prometheus-0
kubectl -n monitoring get pvc prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0
kubectl -n monitoring describe pod prometheus-kube-prometheus-stack-prometheus-0
```

정상 상태:

```text
pod/prometheus-kube-prometheus-stack-prometheus-0   2/2 Running
pvc/...prometheus-0                                Bound  50Gi  RWO  gp2
```

### Slack 알람

Alertmanager Slack 알림은 Kubernetes Secret `monitoring/alertmanager-slack-webhook`의 `url` key를 사용합니다.
원본 webhook URL은 AWS Secrets Manager의 `gympt/prod/remediation-worker` Secret에 `slack_webhook_url` key로 보관합니다.

기본 Alertmanager 라우팅은 `argocd/applications/platform/monitoring.yaml`에 정의되어 있으며, `severity=warning`은 `#alerts-warning`, `severity=critical`은 `#alerts-critical`, 그 외 기본 라우트는 `#alerts`로 전송합니다.

확인:

```bash
kubectl -n monitoring get secret alertmanager-slack-webhook
kubectl -n monitoring get externalsecret alertmanager-slack-webhook
kubectl -n monitoring get prometheusrule
kubectl -n monitoring get servicemonitor
```

`platform/monitoring/alertmanagerconfig-slack.yaml`은 별도 AlertmanagerConfig 방식의 참고 매니페스트입니다. 현재 기본 배포 경로는 kube-prometheus-stack Helm values의 Alertmanager 설정입니다.

### 알람 경로 테스트

운영 서비스에 부하를 주기 전에 synthetic alert로 `PrometheusRule -> Prometheus -> Alertmanager -> Slack` 경로를 먼저 검증합니다.

```bash
# 테스트 알람 적용
kubectl apply -f platform/monitoring/rules/prometheusrule-alert-test.yaml

# 1-2분 뒤 Prometheus에서 firing 확인
kubectl -n monitoring exec prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/alerts

# Alertmanager 수신 확인
kubectl -n monitoring exec alertmanager-kube-prometheus-stack-alertmanager-0 -c alertmanager -- \
  wget -qO- http://localhost:9093/api/v2/alerts

# 테스트 알람 삭제
kubectl delete -f platform/monitoring/rules/prometheusrule-alert-test.yaml
```

`AlertmanagerTestAlwaysFiring`이 Prometheus에서 `firing`, Alertmanager에서 `active`로 보이면 알람 경로는 정상입니다. 테스트 후에는 반복 알림을 막기 위해 반드시 테스트 룰을 삭제합니다.

현재 `AlertmanagerConfig/slack-alerts`가 적용되어 있으면 warning/critical 알림이 Helm 기본 receiver와 AlertmanagerConfig receiver 양쪽으로 라우팅될 수 있습니다. Slack 중복 알림이 보이면 `kubectl -n monitoring get alertmanagerconfig`로 확인한 뒤 라우팅을 하나로 정리합니다.

---

## 🧪 로컬에서 변경사항 테스트

```bash
# Helm 차트 dry-run
helm template backend-api ./charts/backend-api \
  -f ./charts/backend-api/values-prod.yaml

# 매니페스트 검증
kubectl apply --dry-run=client -f <manifest>

# kind/minikube로 테스트
kind create cluster
kubectl apply -f argocd/applications/
```

---

## 🤝 기여하기

1. 기능 브랜치 생성
2. 차트/매니페스트 업데이트
3. 로컬에서 테스트
4. PR 제출
5. 머지 후 ArgoCD가 자동 배포

---

**저장소**: https://github.com/hj-3/gympt-gitops  
**최종 업데이트**: 2026-06-07
