# TeamWork — 프로젝트 지침

## 프로젝트 개요
AI 에이전트 팀을 위한 업무 스킴 및 워크플로우 템플릿 저장소.

## 디렉토리 구조
```
├── .github/          # 이슈/PR 템플릿, CI 워크플로우
├── docs/             # 프로세스 문서
├── scripts/          # 유틸리티 스크립트
└── src/              # 소스 코드 (프로젝트별)
```

## 컨벤션

### 커밋
Conventional Commits: `<type>(<scope>): <subject>`
- type: feat, fix, docs, style, refactor, test, chore
- subject: 50자 이내, 명령형, 소문자 시작, 마침표 없음

### 브랜치
- `main` — 프로덕션
- `develop` — 개발 통합
- `feature/이슈번호-설명`, `fix/이슈번호-설명`, `hotfix/이슈번호-설명`
- develop에서 분기, PR로만 머지

### 코드 스타일
- 린트: `npm run lint`
- 테스트: `npm test`
- PR 전 반드시 린트/테스트 통과 확인

## 에이전트 행동 규칙

### 필수
- 모든 작업은 이슈에서 시작한다
- 이슈 번호를 브랜치명과 커밋에 포함한다
- PR 생성 시 관련 이슈를 `closes #이슈번호`로 연결한다
- 변경 전 기존 코드를 먼저 읽고 이해한다
- 테스트가 통과하는 코드만 PR로 제출한다

### 금지
- main/develop에 직접 push 금지
- 기존 테스트를 삭제하거나 무력화 금지
- 보안 취약점이 있는 코드 커밋 금지
- `--no-verify`, `--force` 플래그 사용 금지

### 릴리스
- 릴리스는 Orchestrator가 담당
- 시맨틱 버저닝: `feat:` → minor, `fix:` → patch, `BREAKING CHANGE` → major
- 태그 push 시 `release.yml`이 자동으로 GitHub Release 생성
- 릴리스 명령어: `git tag v1.x.x && git push origin v1.x.x`

### 역할별 상세
- [에이전트 역할 정의](docs/agent-roles.md)
- [에이전트 워크플로우](docs/agent-workflow.md)
