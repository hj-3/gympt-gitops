# 기여 가이드

GYMPT GitOps 레포지토리에 기여해 주셔서 감사합니다.

## 📝 기여 방법

### 1. 이슈 생성
변경이 필요한 사항이나 버그를 발견하면 먼저 이슈를 생성하세요.

### 2. 브랜치 생성
```bash
git checkout -b feature/your-feature-name
# 또는
git checkout -b fix/your-bug-fix
```

### 3. 변경 작업
- Helm 차트 수정
- Values 파일 업데이트
- Documentation 추가/수정

### 4. 로컬 테스트
```bash
# Helm lint 실행
helm lint charts/[차트명]

# Template 렌더링 확인
helm template [차트명] charts/[차트명] \
  -f charts/[차트명]/values-dev.yaml \
  --debug

# Kubeconform 검증 (선택)
helm template [차트명] charts/[차트명] | kubeconform -
```

### 5. Commit
```bash
git add .
git commit -m "feat: Add new feature X"
```

Commit 메시지 형식:
- `feat:` - 새로운 기능
- `fix:` - 버그 수정
- `docs:` - 문서 변경
- `refactor:` - 리팩토링
- `test:` - 테스트 추가
- `chore:` - 설정 변경

### 6. Push
```bash
git push origin feature/your-feature-name
```

### 7. Pull Request 생성
- 명확한 제목과 설명 작성
- 변경 사항 요약
- 테스트 결과 포함

## 📐 코딩 규칙

### Helm 차트
- 들여쓰기: 2 spaces
- values.yaml에 모든 설정 주석 추가
- 환경별 values-dev.yaml, values-prod.yaml 분리

### YAML 파일
```yaml
# 올바른 예시
apiVersion: v1
kind: Service
metadata:
  name: backend-api
  labels:
    app: backend-api
spec:
  ports:
    - port: 80
      targetPort: 8080
```

### 네이밍 규칙
- 리소스명: kebab-case (예: `backend-api`)
- Label: camelCase (예: `app.kubernetes.io/name`)
- 환경 변수: UPPER_SNAKE_CASE (예: `LOG_LEVEL`)

## ✅ PR 체크리스트

- [ ] `helm lint` 통과
- [ ] Template 렌더링 확인
- [ ] values.yaml 주석 추가
- [ ] README 또는 문서 업데이트
- [ ] CI 테스트 통과

## 🔍 리뷰 프로세스

1. PR 생성
2. 자동 CI 테스트 실행
3. 코드 리뷰어 배정
4. 리뷰 및 수정
5. 승인 후 머지

## 💬 연락처

질문이나 도움이 필요하면:
- GitHub Issues 생성
- Slack #gympt-platform 채널

감사합니다!
