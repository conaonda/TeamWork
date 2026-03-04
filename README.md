# TeamWork

AI 에이전트 팀(Claude Code)과 사람 팀 모두를 위한 업무 스킴 및 워크플로우 템플릿입니다.

## 구성

### 저장소 템플릿
- **이슈 템플릿** — 버그 리포트, 기능 요청, 태스크
- **PR 템플릿** — 변경사항 요약, 체크리스트
- **CI 워크플로우** — PR/Push 시 자동 린트 및 테스트

### 업무 프로세스 문서
- [워크플로우 가이드](docs/workflow-guide.md) — 이슈 → PR → 머지 전체 흐름
- [코드리뷰 가이드](docs/code-review-guide.md) — 리뷰 체크리스트 및 피드백 원칙
- [커밋 컨벤션](docs/commit-convention.md) — Conventional Commits 기반 규칙
- [브랜치 전략](docs/branching-strategy.md) — main/develop/feature/fix/hotfix 구조

### AI 에이전트 팀
- [CLAUDE.md](CLAUDE.md) — 에이전트용 프로젝트 지침
- [에이전트 역할 정의](docs/agent-roles.md) — Developer, Reviewer, Tester, Orchestrator
- [에이전트 워크플로우](docs/agent-workflow.md) — 에이전트 간 협업 흐름

## 시작하기

### 1. 라벨 설정
```bash
./scripts/setup-labels.sh
```

### 2. 브랜치 보호 규칙 (권장)
GitHub Settings → Branches에서 `main`과 `develop` 브랜치에 보호 규칙을 설정하세요:
- PR 리뷰 필수
- CI 통과 필수
- 직접 Push 금지

### 3. AI 에이전트 팀 활용
1. `CLAUDE.md`를 프로젝트에 맞게 수정합니다.
2. 에이전트 역할(Developer, Reviewer, Tester, Orchestrator)을 할당합니다.
3. [에이전트 워크플로우](docs/agent-workflow.md)에 따라 이슈 → PR → 머지 흐름을 실행합니다.

## 활용 예시
- [스프린트 자동화 시나리오](docs/examples/sprint-automation.md) — Claude CLI 루프 기반 스프린트 자동화

```bash
# 3회 스프린트 자동 실행
./scripts/sprint.sh --repo owner/my-app --sprints 3
```

## 적용 방법
이 저장소를 템플릿으로 사용하거나, 필요한 파일을 프로젝트에 복사하세요.
