# 스프린트 자동화 시나리오

Claude CLI를 루프로 반복 실행하여 매 루프가 하나의 스프린트가 되는 자동화 워크플로우입니다.

## 시나리오

> "할 일 관리 웹앱" 프로젝트를 새로 시작한다.
> TeamWork 템플릿을 기반으로 저장소를 구성하고,
> Claude CLI 스프린트 루프를 통해 기능을 점진적으로 구현한다.

## 1단계: 프로젝트 초기 설정

### 저장소 생성 및 템플릿 적용
```bash
# 새 저장소 생성
gh repo create todo-app --public --clone
cd todo-app

# TeamWork 템플릿 파일 복사
cp -r /path/to/TeamWork/.github .
cp -r /path/to/TeamWork/docs .
cp -r /path/to/TeamWork/scripts .

# 라벨 설정
./scripts/setup-labels.sh owner/todo-app

# develop 브랜치 생성
git checkout -b develop
git push -u origin develop
```

### CLAUDE.md 커스터마이징
프로젝트에 맞게 `CLAUDE.md`를 작성합니다:

```markdown
# todo-app — 프로젝트 지침

## 프로젝트 개요
React + Express 기반 할 일 관리 웹 애플리케이션.

## 기술 스택
- Frontend: React 18, TypeScript, Tailwind CSS
- Backend: Express.js, TypeScript
- DB: SQLite (개발), PostgreSQL (프로덕션)
- 테스트: Vitest, Playwright

## 디렉토리 구조
├── client/          # React 프론트엔드
├── server/          # Express 백엔드
├── shared/          # 공유 타입/유틸리티
└── e2e/             # E2E 테스트

## 명령어
- 린트: `npm run lint`
- 테스트: `npm test`
- 개발 서버: `npm run dev`
- 빌드: `npm run build`

## 에이전트 행동 규칙
(TeamWork 기본 규칙 참조)
```

### 초기 이슈 등록
첫 스프린트에서 처리할 이슈를 등록합니다:
```bash
gh issue create --title "[Feature] 프로젝트 초기 구조 설정" \
  --body "React + Express 프로젝트 스캐폴딩 및 기본 설정" \
  --label "type/feature,priority/high"

gh issue create --title "[Feature] 할 일 CRUD API 구현" \
  --body "할 일 생성/조회/수정/삭제 REST API" \
  --label "type/feature,priority/high"

gh issue create --title "[Research] UI 라이브러리 벤치마킹" \
  --body "Tailwind vs MUI vs Chakra UI 비교 분석" \
  --label "type/task,agent/researcher"
```

---

## 2단계: 스프린트 루프 구조

각 스프린트는 Claude CLI를 역할별로 순차 실행하는 것으로 구성됩니다.

### 스프린트 흐름
```
┌─ 스프린트 시작 ──────────────────────────────────────────┐
│                                                          │
│  1. Orchestrator  — 이슈 확인, 할당, 우선순위 결정         │
│       ↓                                                  │
│  2. Researcher    — (필요시) 기술 조사                     │
│       ↓                                                  │
│  3. Developer     — 구현, PR 생성                         │
│       ↓                                                  │
│  4. Reviewer      — 코드리뷰                              │
│       ↓                                                  │
│  5. Tester        — 테스트 작성/검증                       │
│       ↓                                                  │
│  6. Orchestrator  — 머지, 스프린트 정리                    │
│                                                          │
└──────────────────────────── 다음 스프린트 →───────────────┘
```

---

## 3단계: 역할별 프롬프트

### Orchestrator (스프린트 시작)
```
당신은 Orchestrator 에이전트입니다.
저장소: owner/todo-app

다음 작업을 수행하세요:
1. `gh issue list`로 미할당 이슈를 확인하세요.
2. 우선순위를 판단하고 이번 스프린트에서 처리할 이슈를 선택하세요.
3. 기술 조사가 필요한 이슈는 `agent/researcher` 라벨을 지정하세요.
4. 구현 이슈는 `agent/developer` 라벨을 지정하세요.
5. 스프린트 계획을 이슈 코멘트로 남기세요.
```

### Researcher
```
당신은 Researcher 에이전트입니다.
저장소: owner/todo-app

다음 작업을 수행하세요:
1. `agent/researcher` 라벨이 붙은 이슈를 확인하세요.
2. 이슈에 명시된 조사 범위와 비교 기준에 따라 외부 서비스/기술을 조사하세요.
3. 구조화된 비교 표와 권장 사항을 포함한 리포트를 이슈 코멘트로 작성하세요.
4. 조사 완료 후 `status/review` 라벨을 추가하세요.
```

### Developer
```
당신은 Developer 에이전트입니다.
저장소: owner/todo-app

다음 작업을 수행하세요:
1. `agent/developer` 라벨이 붙은 이슈를 확인하세요.
2. develop 브랜치에서 feature/이슈번호-설명 브랜치를 생성하세요.
3. 이슈 요구사항에 따라 구현하세요.
4. 테스트가 통과하는지 확인하세요 (`npm test`).
5. 커밋 컨벤션에 따라 커밋하세요.
6. PR을 생성하세요 (`closes #이슈번호`).
```

### Reviewer
```
당신은 Reviewer 에이전트입니다.
저장소: owner/todo-app

다음 작업을 수행하세요:
1. 리뷰 대기 중인 PR을 확인하세요 (`gh pr list`).
2. PR diff를 분석하세요 (`gh pr diff <number>`).
3. 코드리뷰 가이드에 따라 체크리스트를 검토하세요.
4. 구조화된 리뷰 결과를 제출하세요 (`gh pr review`).
5. 문제가 없으면 승인, 있으면 변경 요청하세요.
```

### Tester
```
당신은 Tester 에이전트입니다.
저장소: owner/todo-app

다음 작업을 수행하세요:
1. 승인된 PR의 변경사항을 확인하세요.
2. 변경된 코드에 대한 테스트가 충분한지 확인하세요.
3. 부족하면 테스트를 추가 작성하여 PR에 커밋하세요.
4. 전체 테스트를 실행하고 결과를 PR 코멘트로 보고하세요.
```

### Orchestrator (스프린트 종료)
```
당신은 Orchestrator 에이전트입니다.
저장소: owner/todo-app

스프린트를 마무리하세요:
1. 승인된 PR을 머지하세요 (`gh pr merge --squash --delete-branch`).
2. 완료된 이슈를 확인하세요.
3. 남은 이슈나 새로 발견된 작업을 이슈로 등록하세요.
4. 스프린트 결과를 요약하세요.
```

---

## 4단계: 자동화 스크립트 실행

```bash
# 스프린트 자동화 실행 (어디서든 실행 가능)
/path/to/TeamWork/scripts/sprint.sh --repo owner/todo-app --workdir ~/git --sprints 3
```

- `--workdir ~/git` — 저장소를 클론/사용할 상위 디렉토리
- 저장소가 없으면 자동 클론, 있으면 기존 체크아웃 사용
- 로그는 `~/git/todo-app/sprint-logs/`에 생성됨

스크립트 상세는 [`scripts/sprint.sh`](../../scripts/sprint.sh)를 참고하세요.

---

## 스프린트 실행 예시

### 스프린트 1: 프로젝트 초기 구조
```
[Sprint 1] 시작
[Orchestrator] 이슈 #1 "프로젝트 초기 구조 설정" 선택 → agent/developer 할당
[Developer] feature/1-project-setup 브랜치 생성 → 스캐폴딩 구현 → PR #4 생성
[Reviewer] PR #4 승인
[Tester] 기본 테스트 설정 확인
[Orchestrator] PR #4 머지 → 이슈 #1 완료
[Sprint 1] 완료
```

### 스프린트 2: 리서치 + API 구현
```
[Sprint 2] 시작
[Orchestrator] 이슈 #3 "UI 라이브러리 벤치마킹" → agent/researcher 할당
              이슈 #2 "할 일 CRUD API" → agent/developer 할당
[Researcher] Tailwind vs MUI vs Chakra 조사 → Tailwind 권장 리포트 제출
[Developer] feature/2-todo-crud-api 브랜치 → API 구현 → PR #5 생성
[Reviewer] PR #5 변경 요청 — 에러 핸들링 보완 필요
[Developer] 피드백 반영
[Reviewer] PR #5 승인
[Tester] API 테스트 추가
[Orchestrator] PR #5 머지 → 이슈 #2 완료, 이슈 #3 완료
[Sprint 2] 완료
```

### 스프린트 3: 프론트엔드 구현
```
[Sprint 3] 시작
[Orchestrator] 새 이슈 생성 "#6 할 일 UI 구현 (Tailwind 적용)"
              이슈 #6 → agent/developer 할당
[Developer] feature/6-todo-ui 브랜치 → React 컴포넌트 구현 → PR #7 생성
[Reviewer] PR #7 승인
[Tester] E2E 테스트 추가
[Orchestrator] PR #7 머지 → 릴리스 판단 → v0.1.0 태그 생성
[Sprint 3] 완료 — v0.1.0 릴리스
```
