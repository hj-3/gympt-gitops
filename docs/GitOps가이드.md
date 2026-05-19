# GitOps 가이드

## GitOps란?

GitOps는 Git을 단일 진실 소스(Single Source of Truth)로 사용하는 운영 방식입니다.

### 핵심 원칙

1. **선언적(Declarative)**: 시스템의 원하는 상태를 선언
2. **버전 관리(Versioned)**: 모든 변경사항은 Git 히스토리로 추적
3. **자동 적용(Automated)**: Git 변경 시 자동으로 클러스터에 반영
4. **지속적 조정(Continuously Reconciled)**: 실제 상태를 원하는 상태로 지속 조정

## Argo CD 개요

Argo CD는 Kubernetes를 위한 선언적 GitOps 지속적 배포 도구입니다.

### 주요 기능

- **자동 동기화**: Git 변경 시 자동 배포
- **Self-Heal**: 클러스터 변경사항 자동 복구
- **롤백**: 이전 버전으로 쉽게 롤백
- **Health Check**: 리소스 상태 모니터링
- **Diff**: Git과 클러스터 상태 비교

## 배포 프로세스

### 1. 코드 변경
```bash
# gympt-app 레포지토리에서 개발
cd gympt-app
git checkout -b feature/new-api
# 코드 수정
git commit -m "Add new API endpoint"
git push
```

### 2. CI/CD 파이프라인
```bash
# GitHub Actions에서 자동 실행
1. Docker 이미지 빌드
2. ECR에 푸시 (태그: git SHA)
3. gympt-gitops 레포 image tag 업데이트
```

### 3. Git Commit (자동)
```bash
# CI/CD에서 자동으로 실행
cd gympt-gitops
sed -i "s|tag:.*|tag: abc1234|g" argocd/applications/dev/backend-api.yaml
git commit -m "[ci] Update backend-api image to abc1234"
git push
```

### 4. Argo CD 감지
- Git Poll (3분마다 자동 확인)
- Webhook (설정 시 즉시 감지)

### 5. Sync 실행
```bash
1. Helm Template 렌더링
2. Diff 계산 (현재 상태 vs 원하는 상태)
3. kubectl apply (변경사항 적용)
4. Health Check (배포 상태 확인)
```

### 6. 배포 완료
- Rolling Update로 Zero Downtime 배포
- 새 Pod가 Ready 상태가 되면 기존 Pod 제거

## Argo CD 명령어

### 애플리케이션 관리

```bash
# 애플리케이션 목록
argocd app list

# 특정 앱 상태 확인
argocd app get backend-api-dev

# 동기화
argocd app sync backend-api-dev

# 동기화 대기
argocd app wait backend-api-dev --sync

# 로그 확인
argocd app logs backend-api-dev

# 히스토리
argocd app history backend-api-dev
```

### 동기화 옵션

```bash
# Prune (Git에 없는 리소스 삭제)
argocd app sync backend-api-dev --prune

# Force (강제 재생성)
argocd app sync backend-api-dev --force

# Dry-run (실제 적용 없이 시뮬레이션)
argocd app sync backend-api-dev --dry-run
```

### Diff 확인

```bash
# 현재 클러스터 상태 vs Git 상태
argocd app diff backend-api-dev

# 상세 Diff
argocd app manifests backend-api-dev | kubectl diff -f -
```

## 롤백

### 방법 1: Argo CD History

```bash
# 배포 히스토리 확인
argocd app history backend-api-dev

# 특정 리비전으로 롤백
argocd app rollback backend-api-dev 5

# 이전 버전으로 롤백
argocd app rollback backend-api-dev
```

### 방법 2: Git Revert

```bash
# 가장 권장되는 방법
cd gympt-gitops
git revert HEAD
git push

# Argo CD가 자동으로 이전 버전 배포
```

### 방법 3: Remediation Worker (자동)

- `BackendPodRestarting` 알람 발생 시 자동으로 이전 버전으로 롤백
- Argo CD API를 통해 실행
- Slack으로 롤백 알림

## App-of-Apps 패턴

계층적으로 애플리케이션을 관리하는 패턴입니다.

### 구조

```
argocd/app-of-apps/dev-apps.yaml (Root Application)
└─> argocd/applications/dev/*.yaml (Child Applications)
    ├─> backend-api
    ├─> agent-service
    ├─> posture-analysis-service
    └─> ...
```

### 장점

- 한 번의 배포로 모든 애플리케이션 관리
- 환경별 분리 (dev, prod)
- 일관된 배포 정책 적용

### 예시

```yaml
# argocd/app-of-apps/dev-apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dev-apps
  namespace: argocd
spec:
  project: gympt-apps
  source:
    repoURL: https://github.com/YOUR_ORG/gympt-gitops.git
    targetRevision: main
    path: argocd/applications/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Sync Waves

배포 순서를 제어합니다.

### 예시

```yaml
# Wave 0: Namespace
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"

# Wave 1: ConfigMap, Secret
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"

# Wave 2: Deployment, Service
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "2"

# Wave 3: Ingress, HPA
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "3"
```

## Health Assessment

리소스 상태를 확인합니다.

### 기본 Health Check

- **Healthy**: 정상 상태
- **Progressing**: 배포 중
- **Degraded**: 문제 발생
- **Suspended**: 일시 중지
- **Missing**: 리소스 없음

### 커스텀 Health Check

```yaml
# Argo CD ConfigMap에 추가
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  resource.customizations: |
    apps/Deployment:
      health.lua: |
        hs = {}
        if obj.status ~= nil then
          if obj.status.conditions ~= nil then
            for i, condition in ipairs(obj.status.conditions) do
              if condition.type == "Progressing" and condition.status == "False" then
                hs.status = "Degraded"
                hs.message = condition.message
                return hs
              end
            end
          end
        end
        hs.status = "Healthy"
        return hs
```

## 모범 사례

### 1. Git = 단일 진실 소스
- 모든 변경은 Git을 통해
- kubectl apply 직접 사용 금지
- 긴급 상황에서도 Git 커밋 후 동기화

### 2. 환경 분리
- Dev/Prod 별도 관리
- 환경별 values 파일 사용
- Namespace 분리

### 3. 자동화
- Self-Heal 활성화
- 자동 Prune 설정
- Sync Retry 설정

### 4. 모니터링
- Sync 상태 모니터링
- Health Check 설정
- Slack/Email 알림 설정

### 5. 보안
- RBAC 설정
- Repository 접근 권한 관리
- Secret 암호화 (Sealed Secrets, External Secrets)

## 참고 자료

- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [GitOps Principles](https://opengitops.dev/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
