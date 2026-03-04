# 에이전트 팀 워크플로우

## 전체 흐름

```
                    ┌────────────┐
               ┌───→│ Researcher │───┐
               │    │ 기술 조사    │   │
               │    └────────────┘   │
┌─────────────┐│                     ▼  ┌──────────┐     ┌──────────────┐
│ Orchestrator│├────────────────────→│ Developer │────→│ Reviewer │────→│ Orchestrator │
│ 이슈 분석    │                     │ 구현 & PR  │     │ 코드리뷰  │     │ 머지          │
└─────────────┘                     └───────────┘     └──────────┘     └──────────────┘
                                                           │
                                                      ┌────┴─────┐
                                                      │  Tester  │
                                                      │ 테스트 검증│
                                                      └──────────┘
```

> Orchestrator가 이슈를 분석하여 기술 조사가 필요하면 Researcher에게 먼저 할당하고, 조사 결과를 바탕으로 Developer가 구현합니다.

## 단계별 상세

### 0. 기술 조사 (Researcher) — 필요 시
```bash
# Orchestrator가 조사 이슈 할당
gh issue edit <number> --add-label "agent/researcher"
gh issue edit <number> --add-assignee researcher-agent

# Researcher가 조사 후 결과를 코멘트로 제출
gh issue comment <number> --body "조사 리포트 내용"

# 상세 리포트는 docs/research/에 커밋
```

### 1. 이슈 할당 (Orchestrator)
```bash
# 미할당 이슈 확인
gh issue list --repo <repo> --assignee "" --state open

# 이슈 분석 후 할당 및 라벨 지정
gh issue edit <number> --add-assignee developer-agent
gh issue edit <number> --add-label "priority/high"
```

### 2. 구현 (Developer)
```bash
# 이슈 확인
gh issue view <number>

# 브랜치 생성 및 작업
git checkout develop
git pull origin develop
git checkout -b feature/<number>-description

# 구현 후 테스트 통과 확인
npm test

# 커밋 및 PR 생성
git add <files>
git commit -m "feat(<scope>): 설명 (#<number>)"
git push -u origin feature/<number>-description
gh pr create --title "feat: 설명" --body "closes #<number>" --base develop
```

### 3. 코드리뷰 (Reviewer)
```bash
# PR 확인
gh pr view <number>
gh pr diff <number>

# 리뷰 제출
gh pr review <number> --approve --body "리뷰 결과"
# 또는
gh pr review <number> --request-changes --body "변경 요청 내용"
```

### 4. 테스트 검증 (Tester)
- CI가 자동으로 실행
- 추가 테스트가 필요한 경우 Tester 에이전트가 테스트 코드를 작성하여 PR에 추가

### 5. 머지 (Orchestrator)
```bash
# CI 통과 및 리뷰 승인 확인
gh pr checks <number>
gh pr view <number> --json reviews

# 머지
gh pr merge <number> --squash --delete-branch
```

## 에이전트 간 커뮤니케이션

에이전트 간 소통은 **GitHub 이슈/PR 코멘트**를 통해 이루어진다.

### 코멘트 형식
```markdown
**@역할** 메시지

예:
**@reviewer** 이 PR의 인증 로직을 중점적으로 확인해 주세요.
**@developer** L42의 null 체크가 누락되었습니다. 수정 부탁합니다.
```

### 상태 전달
이슈/PR 라벨로 현재 상태를 표시한다:
- `status/in-progress` — 작업 중
- `status/review` — 리뷰 대기
- `status/blocked` — 블로킹 이슈

## 충돌 처리
1. Developer가 머지 충돌 발생 시 `develop`을 rebase
2. 해결 불가 시 이슈 코멘트로 Orchestrator에게 보고
3. Orchestrator가 우선순위 기반으로 해결 방향 결정

---

## 릴리스 워크플로우 (Orchestrator)

```
develop 안정화 → 버전 결정 → develop→main PR → 머지 → 태그 → GitHub Release
```

### 단계별 상세
```bash
# 1. 마지막 릴리스 이후 변경사항 확인
gh pr list --base develop --state merged --search "merged:>2024-01-01"

# 2. 버전 결정 (커밋 타입 기반)
#    feat: → minor (1.x.0)
#    fix:  → patch (1.0.x)
#    BREAKING CHANGE → major (x.0.0)

# 3. 릴리스 PR 생성
gh pr create --title "release: v1.2.0" --base main --head develop \
  --body "## Release v1.2.0\n\n변경사항 요약"

# 4. 머지 후 태그 및 릴리스 생성
git tag v1.2.0
git push origin v1.2.0
# release.yml 워크플로우가 자동으로 GitHub Release 생성
```

## CI 실패 대응 (Orchestrator)

```
CI 실패 감지 → 로그 분석 → 수정 이슈 생성 → Developer 할당
```

```bash
# 1. 실패한 CI 확인
gh run list --status failure --limit 5

# 2. 실패 로그 분석
gh run view <run-id> --log-failed

# 3. 수정 이슈 생성
gh issue create --title "[Fix] CI 실패: 원인 설명" \
  --body "## CI 실패 정보\n- Run: <run-url>\n- 원인: ...\n- 수정 방향: ..." \
  --label "type/bug,priority/high" \
  --assignee developer-agent
```
