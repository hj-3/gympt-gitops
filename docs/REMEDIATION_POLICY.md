# Remediation 정책

## 목적

이 문서는 GYMPT 플랫폼의 자동복구 정책, 허용 액션, 금지 액션, 환경별 안전장치, 감사 로그 기준을 정의한다.

자동복구의 목적은 반복적이고 위험도가 낮은 장애 대응을 빠르게 처리하는 것이다. 운영 환경에서 데이터 손실, 잘못된 rollback, 장애 확대를 만들 수 있는 액션은 자동 실행하지 않는다.

## 기본 원칙

- 자동복구는 알람 기반으로만 실행한다.
- 모든 액션은 cooldown을 가진다.
- 모든 액션은 감사 로그를 남긴다.
- prod 환경의 파괴적 액션은 기본적으로 제한한다.
- 처음 도입할 때는 `DRY_RUN=true`로 시작한다.
- GitOps 원칙을 깨는 변경은 임시 조치로만 허용한다.
- 자동복구 후 Git 상태와 클러스터 상태가 어긋나면 Git을 기준으로 정리한다.

## 환경별 정책

### dev

dev에서는 자동복구를 적극적으로 검증할 수 있다.

허용:

- notify_only
- restart_deployment
- scale_deployment
- rollback_argocd
- run_job 테스트

권장:

```yaml
DRY_RUN: "true"
```

초기 검증 후 특정 alert만 `dryRun: false`로 전환한다.

### prod

prod에서는 자동복구를 제한적으로만 허용한다.

허용:

- notify_only
- scale_deployment
- restart_deployment 일부

제한:

- rollback_argocd
- run_job
- patch_deployment

prod rollback은 기본적으로 notify-only 또는 수동 승인 기반으로 처리한다.

## 액션 분류

### notify_only

알림만 발송하고 클러스터를 변경하지 않는다.

사용 대상:

- AWS managed service 장애 의심
- Redis 장애
- Bedrock throttling
- GPU capacity 부족
- DLQ message 발생
- 원인이 명확하지 않은 prod 장애

### restart_deployment

Deployment rolling restart를 수행한다.

허용 조건:

- stateless service
- 최근 동일 액션 cooldown 미발생
- restart 횟수 제한 이내
- DB migration 또는 batch job 실행 중이 아님

prod에서는 다음 서비스부터 제한적으로 허용한다.

```text
backend-api
agent-service
report-service
```

### scale_deployment

Deployment replica 수를 증가 또는 감소시킨다.

허용 조건:

- HPA maxReplicas 이하
- action limit 이내
- queue backlog 또는 latency 증가처럼 scale로 완화 가능한 알람

prod에서는 scale up만 우선 허용한다. scale down은 HPA 또는 수동 조정에 맡긴다.

### rollback_argocd

Argo CD Application을 이전 revision으로 rollback한다.

dev에서는 허용할 수 있다.

prod에서는 기본 금지한다. 필요한 경우 다음 절차를 따른다.

```text
1. critical alert 발생
2. 원인 확인
3. 담당자 승인
4. Argo CD rollback 또는 Git revert
5. GitOps values 상태 정리
```

GitOps 기준에서는 Git revert를 우선한다.

### run_job

Kubernetes Job을 실행한다.

사용 대상:

- 캐시 정리
- 임시 진단
- 안전한 repair script

prod에서는 사전 승인된 Job template만 허용한다.

### patch_deployment

Deployment spec을 patch한다.

prod에서는 기본 금지한다.

허용하려면 patch 대상, patch 내용, rollback 방법이 runbook에 있어야 한다.

## 안전장치

### Dry-run

자동복구 도입 초기 기본값:

```yaml
DRY_RUN: "true"
```

dry-run 모드에서는 다음만 수행한다.

- alert 수신
- 실행 예정 action 계산
- Slack 알림
- 로그 기록
- metrics 기록

### Cooldown

같은 대상에 반복 액션을 막기 위해 cooldown을 둔다.

권장:

```text
restart_deployment: 10분
scale_deployment: 10분
rollback_argocd: 30분
notify_only: 5분
```

### Action limit

시간당 최대 액션 수를 제한한다.

권장:

```text
maxRestartsPerHour: 3
maxScaleUpsPerHour: 5
maxRollbacksPerHour: 1
```

### 제외 대상

자동복구에서 제외할 namespace:

```text
kube-system
kube-public
kube-node-lease
argocd
monitoring
external-secrets
```

자동복구에서 제외할 deployment:

```text
argocd-server
argocd-repo-server
kube-prometheus-stack
external-secrets
remediation-worker
```

## RBAC 기준

remediation-worker의 Kubernetes 권한은 최소 권한으로 제한한다.

필요 권한:

```text
get/list/watch pods
get/list/watch deployments
patch deployments
patch deployments/scale
create events
get configmaps
```

제한 권한:

```text
delete namespace
delete deployment
delete pvc
delete secret
patch clusterrole
patch clusterrolebinding
```

Argo CD rollback 권한은 별도 service account 또는 별도 token으로 분리한다.

## 감사 로그 기준

모든 remediation action은 다음 정보를 남긴다.

```text
timestamp
environment
alertName
severity
namespace
deployment
action
dryRun
cooldownApplied
beforeState
afterState
gitRevision
argocdApplication
result
errorMessage
triggeredBy
```

Slack 알림에는 최소 다음을 포함한다.

```text
alertName
target
action
result
dryRun 여부
runbook link
dashboard link
```

## Alert-to-Action 매핑 기준

### BackendHighErrorRate

dev:

```text
restart_deployment
```

prod:

```text
notify_only 또는 restart_deployment 제한 허용
```

### BackendHighLatency

dev/prod:

```text
scale_deployment up
```

### BackendPodRestarting

dev:

```text
rollback_argocd 가능
```

prod:

```text
notify_only
```

### SQSQueueBacklog

dev/prod:

```text
scale_deployment up
```

### SQSDLQMessages

dev/prod:

```text
notify_only
```

DLQ는 자동 삭제하거나 자동 재처리하지 않는다.

### RedisConnectionError

dev/prod:

```text
notify_only
```

AWS managed service 장애 또는 네트워크 문제일 수 있으므로 자동 restart로 해결하려 하지 않는다.

### BedrockThrottling

dev/prod:

```text
notify_only
```

필요 시 rate limit, retry policy, quota increase를 별도 처리한다.

## 운영 절차

### 자동복구 활성화 절차

1. alert rule 작성
2. runbook 작성
3. dry-run으로 alert 수신 확인
4. Slack 알림 확인
5. staging 또는 dev에서 실제 action 확인
6. action limit 및 cooldown 확인
7. prod에서는 notify-only부터 적용
8. 승인 후 제한적 action 허용

### 자동복구 비활성화 절차

전역 비활성화:

```bash
kubectl set env deployment/remediation-worker -n workers DRY_RUN=true
```

특정 alert 비활성화:

```yaml
- alertName: BackendHighErrorRate
  dryRun: true
```

특정 deployment 제외:

```yaml
excludedDeployments:
  - backend-api
```

## 현재 구체화가 필요한 항목

- dev/prod remediation values 분리
- prod 기본값 `DRY_RUN=true` 적용
- prod rollback action notify-only 전환
- remediation-worker RBAC manifest 추가
- Alertmanager webhook 연동 방식 정의
- Slack webhook secret을 ExternalSecret으로 관리
- Argo CD token secret 관리 방식 정의
- remediation action metrics 정의
- action audit log 저장 위치 정의
