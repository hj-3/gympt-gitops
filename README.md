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

## 🛡️ 엣지/네트워크 보안

### Prod service Ingress (shared ALB)

`backend-api`와 `posture-analysis-service`는 `alb.ingress.kubernetes.io/group.name: gympt-prod`로 같은 internet-facing ALB를 공유합니다.

- **WAF**: `alb.ingress.kubernetes.io/wafv2-acl-arn` 으로 Regional WAF(`gympt-alb-waf`) 연결
  - AWS Managed Rules (CommonRuleSet / SQLi / KnownBadInputs / AdminProtection) + IP 기반 Rate Limit(2000 req / 5분)
  - `api.g2mpt.com`, `posture.g2mpt.com`은 CloudFront를 경유하지 않고 ALB 직접 구조이므로, X-Custom-Header 오리진 보호 대신 **WAF를 ALB에 직접 적용**해 보호
- **Access Logs**: `access_logs.s3.enabled=true` 로 ALB 액세스 로그를 S3 중앙 로그 버킷(`gympt-prod-logs/alb-access-logs/`)에 적재
- **IngressGroup**: `group.order`는 backend-api `10`, posture-analysis `20`으로 고정해 listener rule 우선순위를 명시합니다.

> WAF web ACL과 Firehose 등 AWS 리소스 자체는 gympt-infra(또는 콘솔)에서 관리하며, GitOps에서는 ingress annotation으로 ALB에 연결합니다. annotation을 제거하면 AWS Load Balancer Controller가 WAF 연결을 해제하므로 주의하세요.

### agent-service AI 보안 (Bedrock Guardrail)

agent-service의 Bedrock Agent에 Guardrail(`gympt-prod-guardrail`, us-west-2)을 연결해 AI 입출력을 보호합니다.

- **콘텐츠 필터**: 유해 카테고리(증오/모욕/성적/폭력/위법) + 프롬프트 공격(인젝션) 방어, 한국어 지원(Standard tier)
- **PII 보호**: 이름/이메일/전화/주소/나이 마스킹, 비밀번호/카드/AWS키 차단, 주민번호(정규식) 마스킹
- **이미지 보안(CI)**: 컨테이너 빌드 시 Trivy 취약점 스캔(리포트) + ECR scan-on-push 이중 스캔

> Guardrail은 콘솔에서 생성해 Bedrock Agent에 연결합니다(앱 코드 수정 불필요). 자세한 빌드 보안은 `gympt-app` README의 CI/CD 섹션 참고.

---

## 📊 모니터링

### Grafana 접근

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
open http://localhost:3000
# admin / [secret의 비밀번호]
```

### Grafana Athena datasource

Grafana는 `Athena` datasource를 통해 중앙 S3 로그 버킷의 Glue Catalog Table을 조회합니다.

설정값:

```text
Plugin: grafana-athena-datasource
Region: ap-northeast-2
Catalog: AwsDataCatalog
Database: gympt_prod_catalog
Workgroup: gympt-prod-workgroup
Output: s3://gympt-prod-athena-results-337112169365/athena-results/
```

WAF/Inspector table은 partition projection을 사용하므로 panel query에 `year/month/day/hour` 조건을 넣어 S3 scan 범위를 제한합니다.

```sql
SELECT action, httprequest.clientip, httprequest.uri
FROM waf_alb_logs
WHERE year='2026'
  AND month='06'
  AND day='08'
  AND hour='00'
LIMIT 100;
```

### Grafana ALB Ingress

Grafana Ingress는 AWS Load Balancer Controller의 `alb` IngressClass를 사용합니다. Grafana Service는 `ClusterIP` 타입이므로 ALB target group은 Pod IP를 직접 대상으로 잡아야 합니다.

필수 annotation:

```yaml
grafana:
  ingress:
    enabled: true
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/healthcheck-path: /api/health
```

`target-type`이 없으면 ALB Controller 기본값인 `instance` 모드로 target group을 만들려고 합니다. 이 경우 Service에 NodePort가 없어 target group port가 `0`으로 계산되고, AWS API에서 아래 오류가 발생합니다.

```text
InvalidParameter: minimum field value of 1, CreateTargetGroupInput.Port
```

확인:

```bash
kubectl -n monitoring describe ingress kube-prometheus-stack-grafana
kubectl -n kube-system logs deploy/aws-load-balancer-controller --since=10m
```

정상 상태에서는 Ingress 이벤트에 `SuccessfullyReconciled`가 보이고, ALB Controller 모델의 target group이 `targetType: ip`, `port: 3000`으로 생성됩니다.

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
**최종 업데이트**: 2026-06-08
