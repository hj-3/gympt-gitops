# CI/CD 전략

## 목적

이 문서는 GYMPT 프로젝트의 CI/CD 역할 분리, 레포지토리별 책임, dev/prod 배포 방식, GitOps 업데이트 기준을 정의한다.

CI/CD의 핵심 원칙은 다음과 같다.

- GitHub Actions는 빌드, 테스트, 이미지 생성, ECR Push, 프론트엔드 배포, GitOps 값 업데이트를 담당한다.
- Argo CD는 GitOps 레포지토리에 선언된 상태를 기준으로 EKS 클러스터를 동기화한다.
- Terraform은 AWS 인프라 생성과 변경을 담당한다.
- Helm은 Kubernetes 리소스 템플릿과 환경별 values 관리를 담당한다.

## 레포지토리별 역할

### gympt-app

애플리케이션 소스 코드와 앱 CI/CD를 관리한다.

- Frontend 빌드
- S3 배포
- CloudFront invalidation
- Backend API 빌드 및 테스트
- Python 서비스 lint/test
- Docker image build
- ECR push
- Lambda package 생성
- GitOps 레포지토리의 image tag 업데이트

주요 workflow:

- `.github/workflows/frontend-deploy.yml`
- `.github/workflows/backend-api-ci.yml`
- `.github/workflows/agent-service-ci.yml`
- `.github/workflows/posture-analysis-service-ci.yml`
- `.github/workflows/report-service-ci.yml`
- `.github/workflows/kvs-consumer-service-ci.yml`
- `.github/workflows/lambda-package.yml`

### gympt-infra

Terraform 기반 AWS 인프라 변경을 관리한다.

- Terraform fmt
- Terraform validate
- Terraform plan
- Terraform apply
- 보안 검사
- 인프라 변경 승인

주요 workflow:

- `.github/workflows/terraform-plan.yml`
- `.github/workflows/terraform-apply.yml`

### gympt-gitops

Kubernetes 배포 선언과 플랫폼 운영 리소스를 관리한다.

- Helm chart
- dev/prod values
- Argo CD Application
- ExternalSecret
- ServiceMonitor
- PrometheusRule
- Grafana dashboard
- NetworkPolicy
- Remediation 설정

주요 workflow:

- `.github/workflows/helm-lint.yml`
- `.github/workflows/kubeconform.yml`

## 브랜치별 배포 전략

### dev 배포

`gympt-app`의 `develop` 브랜치 push를 기준으로 dev 배포를 수행한다.

흐름:

```text
develop push
-> GitHub Actions test/build
-> Docker image build
-> ECR dev repository push
-> gympt-gitops values-dev.yaml image tag 업데이트
-> Argo CD dev Application sync
-> EKS dev 배포
```

dev는 빠른 피드백을 위해 GitOps values 변경을 자동 commit 할 수 있다.

### prod 배포

`gympt-app`의 `main` 브랜치 merge를 기준으로 prod 후보 이미지를 생성한다.

흐름:

```text
main push
-> GitHub Actions test/build
-> Docker image build
-> ECR prod repository push
-> gympt-gitops values-prod.yaml 변경 PR 생성
-> 리뷰 및 승인
-> PR merge
-> Argo CD prod Application sync
-> EKS prod 배포
```

prod는 직접 push보다 PR 기반 변경을 원칙으로 한다. 배포 이력, 리뷰 이력, 롤백 기준을 Git에 남기기 위해서다.

## 이미지 태그 정책

`latest`와 `dev-latest`는 배포 추적이 어렵기 때문에 사용하지 않는다.

권장 태그:

```text
{git-sha-7자리}
```

예:

```text
backend-api:a91c3f2
agent-service:bb91f8a
posture-analysis-service:c73aa21
```

필요하면 GitHub Actions run number를 접두사로 붙일 수 있다.

```text
{run-number}-{git-sha-7자리}
```

단, 모든 서비스에서 같은 규칙을 사용해야 한다.

## GitOps 업데이트 기준

GitHub Actions가 수정해야 하는 대상은 서비스별 values 파일의 `image.tag`이다.

예:

```text
charts/backend-api/values-dev.yaml
charts/backend-api/values-prod.yaml
charts/agent-service/values-dev.yaml
charts/agent-service/values-prod.yaml
```

수정 대상:

```yaml
image:
  repository: 337112169365.dkr.ecr.ap-northeast-2.amazonaws.com/gympt-prod/backend-api
  tag: "a91c3f2"
```

운영 원칙:

- dev: `values-dev.yaml` 직접 commit 허용
- prod: `values-prod.yaml` 변경 PR 생성
- PR 제목에는 서비스명, 환경, 이미지 태그를 포함
- commit message에는 원본 app commit SHA를 포함

## GitHub Actions 인증 전략

AWS 장기 Access Key 사용을 금지한다.

GitHub Actions는 OIDC로 AWS IAM Role을 Assume한다.

권장 role:

```text
github-actions-app-dev-role
github-actions-app-prod-role
github-actions-infra-dev-role
github-actions-infra-prod-role
```

권한 분리:

- frontend deploy role: S3 sync, CloudFront invalidation
- ecr push role: ECR login, image push
- terraform plan role: read 및 plan 권한
- terraform apply role: 인프라 변경 권한
- gitops update role: GitOps PR 또는 commit 권한

GitHub Actions 예시:

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: ${{ vars.AWS_ROLE_DEV }}
      aws-region: ap-northeast-2
```

## 검증 기준

### gympt-app

Frontend:

- `npm ci`
- lint
- type check
- build

Backend API:

- Java 21 setup
- Gradle test
- Gradle build
- Docker build

Python services:

- ruff
- pytest
- Docker build

Lambda:

- dependency install
- test
- package validation
- artifact upload

### gympt-gitops

- YAML validation
- Helm lint
- Helm template dev/prod
- kubeconform
- Argo CD Application manifest validation

### gympt-infra

- Terraform fmt
- Terraform validate
- Terraform plan
- TFLint
- Checkov
- 수동 승인 후 apply

## 롤백 기준

GitOps 롤백은 Git revert를 우선한다.

```bash
git revert <gitops-values-update-commit>
git push
```

긴급 상황에서는 Argo CD rollback을 사용할 수 있다.

```bash
argocd app rollback backend-api-prod <revision>
```

단, Argo CD rollback 후에는 Git 상태도 반드시 동일하게 맞춘다.

## 현재 구체화가 필요한 항목

- Argo CD Application의 `repoURL` 통일
- dev/prod namespace 전략 통일
- app workflow의 AWS Access Key 제거 및 OIDC 전환
- prod GitOps 업데이트를 직접 push에서 PR 생성 방식으로 변경
- 테스트 실패 무시(`|| true`) 제거
- `latest`, `dev-latest` 이미지 태그 제거
