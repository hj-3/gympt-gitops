# CI/CD Runbook

## 목적

이 문서는 `gympt-gitops` 저장소의 PR 검증, Helm chart 렌더링, kubeconform 검증, Argo CD 동기화 문제를 빠르게 확인하고 대응하기 위한 운영 runbook이다.

## PR 검증 흐름

`dev`에서 작업한 변경은 `main`으로 PR을 열어 검증한다.

```text
dev push
-> dev -> main PR 생성
-> Helm Lint and Test
-> Kubeconform Validation
-> 리뷰
-> merge
-> Argo CD가 main 기준으로 sync
```

PR에서 확인할 위치:

- PR 화면의 `Checks` 탭
- 저장소의 `Actions` 탭
- 실패한 workflow의 실패 job과 step 로그

Actions 탭에 GitHub Actions 소개 화면만 보이면 기본 브랜치에 workflow가 아직 없거나, workflow가 GitHub에서 인식되지 않은 상태일 수 있다.

## 로컬 확인 명령

가능하면 `gympt-gitops` 루트에서 먼저 확인한다.

```bash
helm lint charts/backend-api
helm lint charts/agent-service
helm lint charts/posture-analysis-service
helm lint charts/report-service
helm lint charts/remediation-worker
```

values 파일별 렌더링:

```bash
helm template posture-analysis-service charts/posture-analysis-service \
  -f charts/posture-analysis-service/values-dev.yaml \
  --debug
```

전체 values 파일 렌더링 패턴:

```bash
for chart in backend-api agent-service posture-analysis-service report-service remediation-worker; do
  for values_file in charts/$chart/values*.yaml; do
    helm template "$chart" "charts/$chart" -f "$values_file" --debug
  done
done
```

## 자주 나는 에러

### Helm filter 함수 에러

에러:

```text
Error: parse error at (.../templates/configmap.yaml): function "filter" not defined
```

원인:

Helm template에서 지원하지 않는 `filter` 함수를 사용한 경우다.

대응:

`range`와 `if eq`를 사용해 값 탐색 로직으로 바꾼다.

```yaml
{{- $metricsPort := "8000" }}
{{- range .Values.env }}
{{- if eq .name "METRICS_PORT" }}
{{- $metricsPort = .value }}
{{- end }}
{{- end }}
port = {{ $metricsPort }}
```

### values-dev.yaml 없음

에러:

```text
Error: open charts/posture-analysis-service/values-dev.yaml: no such file or directory
```

원인:

Argo CD Application이나 workflow가 `values-dev.yaml`을 참조하지만 chart 디렉터리에 파일이 없는 경우다.

대응:

해당 chart에 dev values를 추가한다.

확인:

```bash
find charts -maxdepth 2 -name 'values*.yaml' -print
```

특히 `argocd/applications/dev/*.yaml`에서 참조하는 chart는 `values-dev.yaml`이 있어야 한다.

### kubeconform CRD schema 없음

에러:

```text
could not find schema for Application
could not find schema for AppProject
could not find schema for ServiceMonitor
could not find schema for ExternalSecret
```

원인:

Kubernetes 기본 리소스가 아닌 CRD 리소스를 검증할 때 kubeconform이 CRD schema를 찾지 못한 경우다.

대응:

workflow에서 CRDs catalog schema location을 추가한다.

```yaml
-schema-location default
-schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```

### setup-helm GITHUB_TOKEN 에러

에러:

```text
Error while fetching latest Helm release:
[@octokit/auth-action] `GITHUB_TOKEN` variable is not set
```

원인:

`azure/setup-helm`에서 Helm 버전을 지정하지 않으면 최신 릴리즈를 GitHub API로 조회하면서 token 문제가 날 수 있다.

대응:

모든 `azure/setup-helm@v3` step에 버전을 고정한다.

```yaml
- name: Setup Helm
  uses: azure/setup-helm@v3
  with:
    version: '3.13.0'
```

확인:

```bash
rg -n -C 2 'azure/setup-helm@v3' .github/workflows
```

## Terraform destroy 이후 주의점

Terraform destroy 이후에도 PR의 Helm/kubeconform 검증은 파일 기반이라 통과할 수 있다. 하지만 merge 이후 Argo CD sync는 실제 클러스터와 AWS 리소스 상태에 영향을 받는다.

merge 전에 확인할 것:

- destroy 대상이 dev인지 prod인지
- EKS cluster가 존재하는지
- Argo CD가 살아 있는지
- ExternalSecret, ServiceMonitor 같은 CRD가 설치되어 있는지
- IRSA IAM role ARN이 아직 존재하는지
- ECR repository와 image tag가 존재하는지

인프라가 없는 상태에서 merge하면 GitHub Actions는 통과해도 Argo CD sync가 실패할 수 있다.

## Argo CD 확인

클러스터 접근이 가능하면 다음 순서로 본다.

```bash
argocd app list
argocd app get backend-api-dev
argocd app diff backend-api-dev
argocd app sync backend-api-dev --dry-run
```

Kubernetes 리소스 상태:

```bash
kubectl get applications -n argocd
kubectl get pods -A
kubectl get events -A --sort-by=.lastTimestamp
```

## Merge 전 체크리스트

- PR의 `Helm Lint and Test`가 통과했다.
- PR의 `Kubeconform Validation`이 통과했다.
- `values-dev.yaml`과 `values-prod.yaml` 참조가 실제 파일과 일치한다.
- workflow에서 Helm 버전이 고정되어 있다.
- CRD schema 검증 경로가 설정되어 있다.
- Terraform apply 이후 인프라와 Argo CD 상태를 확인했다.
- prod 변경이면 팀 리뷰와 승인 후 merge한다.

## 실패 로그를 볼 때 우선순위

1. 실패한 workflow 이름을 확인한다.
2. 실패한 job matrix의 chart 이름을 확인한다.
3. 실패 step 이름을 확인한다.
4. `Error:`, `::error::`, `failed validation`, `no such file or directory` 줄을 먼저 본다.
5. 같은 유형의 에러가 다른 chart에도 반복될지 확인한다.
