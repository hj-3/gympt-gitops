# GYMPT GitOps

Kubernetes 매니페스트 및 Helm 차트 저장소

## 📋 개요

GYMPT 플랫폼의 모든 Kubernetes 리소스를 GitOps 방식으로 관리합니다.

### GitOps 원칙
- 📝 선언적 구성 (모든 것이 YAML)
- 🔄 Git = 단일 진실 소스
- 🤖 자동 동기화 (Argo CD)
- 📜 감사 가능 (Git 이력)
- ⏮️ 쉬운 롤백

## 🏗️ 구조

### Helm 차트 (7개)
- backend-api
- agent-service
- posture-analysis-service
- report-service
- notification-service
- remediation-worker
- generic-worker

### Platform 서비스
- **monitoring** - Prometheus + Grafana
- **logging** - Fluent Bit
- **remediation** - 자동 복구
- **external-secrets** - AWS Secrets Manager 통합
- **network-policies** - Zero-Trust 네트워크

### Argo CD
- App-of-Apps 패턴
- Dev/Prod 환경 분리
- 자동 동기화 및 Self-Heal

## 🚀 빠른 시작

### 사전 요구사항
- Kubernetes 클러스터 (EKS)
- kubectl
- Helm 3.x
- Argo CD CLI

### Argo CD 설치

```bash
# Argo CD 설치
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Admin 비밀번호
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# 포트 포워딩
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### 애플리케이션 배포

```bash
# 프로젝트 생성
kubectl apply -f argocd/projects/

# App-of-Apps 배포
kubectl apply -f argocd/app-of-apps/dev-apps.yaml

# 상태 확인
argocd app list
```

### Platform 서비스 설치

```bash
# Monitoring
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -f platform/monitoring/values-dev.yaml \
  --namespace monitoring --create-namespace

# External Secrets Operator
helm install external-secrets external-secrets/external-secrets \
  -f platform/external-secrets/values.yaml \
  --namespace external-secrets --create-namespace

# NetworkPolicy 적용
./scripts/apply-network-policies.sh dev
```

## 📖 문서

- [GitOps 가이드](docs/GitOps가이드.md)
- [Helm 차트](docs/Helm차트.md)
- [Platform 서비스](docs/Platform서비스.md)
- [배포 절차](docs/배포절차.md)
- [트러블슈팅](docs/트러블슈팅.md)

## 🔧 주요 스크립트

- `apply-network-policies.sh` - NetworkPolicy 배포
- `test-connectivity.sh` - 연결성 테스트
- `verify-completion.sh` - 완성도 검증

## 📦 Helm 차트 구조

각 차트는 다음을 포함:
- Chart.yaml
- values.yaml, values-dev.yaml, values-prod.yaml
- templates/ (Deployment, Service, HPA, PDB 등)

## 🛡️ 보안

- **External Secrets**: AWS Secrets Manager 통합
- **NetworkPolicy**: Zero-Trust 네트워크 격리
- **IRSA**: IAM Roles for Service Accounts
- **PodSecurityPolicy**: Pod 보안 표준

## 📊 모니터링

- **Prometheus**: 메트릭 수집
- **Grafana**: 대시보드 (6개)
- **Alertmanager**: 알림 라우팅
- **ServiceMonitor**: 자동 메트릭 스크래핑

## 🔄 CI/CD

GitHub Actions로 자동화:
- Helm lint
- Kubeconform 검증
- Dev 환경 자동 동기화

## 🤝 기여하기

[CONTRIBUTING.md](CONTRIBUTING.md) 참고

---

---

## 📦 버전

**Current Version:** `0.1.0`

**Changelog:** [CHANGELOG.md](../CHANGELOG.md)

---

**상태**: Production Ready ✅  
**마지막 업데이트**: 2026-05-19
