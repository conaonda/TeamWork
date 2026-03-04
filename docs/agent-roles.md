# 에이전트 역할 정의

## 역할 개요

| 역할 | 책임 | 트리거 |
|------|------|--------|
| Orchestrator | 이슈 분배, 우선순위 관리, 머지 판단, 릴리스/CI 관리 | 새 이슈 생성, PR 리뷰 완료, CI 실패, 릴리스 시점 |
| Developer | 이슈 기반 구현, 브랜치 작업, PR 생성 | 이슈 할당 |
| Reviewer | 코드리뷰, 보안/품질 체크 | PR 생성 |
| Tester | 테스트 작성 및 실행, 커버리지 확인 | PR 생성, 코드 변경 |
| Researcher | 외부 서비스/기술 벤치마킹, 기술 조사 | Orchestrator 할당 (agent/researcher 라벨) |

---

## Orchestrator

**책임:**
- 새 이슈를 분석하고 적절한 에이전트에게 할당
- 이슈 우선순위 및 라벨 관리
- PR 리뷰 완료 후 머지 여부 판단
- 충돌 발생 시 해결 방향 결정
- **릴리스 관리**: develop→main PR 생성, 시맨틱 버저닝 태그, GitHub Release 생성
- **CI 관리**: 파이프라인 실패 분석, 워크플로우 설정 유지보수

**입력:** 이슈 목록, PR 상태, CI 결과
**출력:** 이슈 할당, 머지 실행, 상태 업데이트, 릴리스 태그

**사용 명령어:**
```bash
# 이슈/PR 관리
gh issue list --repo <repo>
gh issue edit <number> --add-assignee <agent>
gh pr merge <number> --squash

# 릴리스
gh pr create --title "release: v1.x.x" --base main --head develop
git tag v1.x.x
git push origin v1.x.x
gh release create v1.x.x --generate-notes

# CI 실패 대응
gh run list --status failure
gh run view <run-id> --log-failed
```

### 릴리스 워크플로우
1. develop에 충분한 변경이 누적되면 릴리스 판단
2. 커밋 타입 기반으로 버전 결정 (`feat:` → minor, `fix:` → patch, `BREAKING CHANGE` → major)
3. develop→main PR 생성 및 머지
4. 태그 생성 → GitHub Release 자동 생성 (release.yml)

### CI 실패 대응 흐름
1. CI 실패 감지 (`gh run list --status failure`)
2. 실패 로그 분석 (`gh run view <id> --log-failed`)
3. 원인 파악 후 수정 이슈 생성 → Developer에게 할당

---

## Developer

**책임:**
- 할당된 이슈를 분석하고 구현
- 브랜치 생성, 커밋, PR 생성
- 커밋 컨벤션 및 브랜치 전략 준수
- PR 피드백 반영

**입력:** 할당된 이슈 (요구사항, 수락 기준)
**출력:** 구현 코드, PR

**워크플로우:**
1. 이슈 내용 확인 → 기존 코드 파악
2. `develop`에서 `feature/이슈번호-설명` 브랜치 생성
3. 구현 및 테스트 통과 확인
4. PR 생성 (`closes #이슈번호`)

---

## Reviewer

**책임:**
- PR 코드를 검토하고 피드백 제공
- 보안 취약점, 성능 이슈, 코드 품질 확인
- 승인 또는 변경 요청

**입력:** PR diff, 관련 이슈
**출력:** 리뷰 코멘트 (구조화된 형식)

**리뷰 출력 형식:**
```markdown
## 리뷰 결과: [승인/변경요청]

### 체크리스트
- [x] 요구사항 충족
- [x] 보안 취약점 없음
- [ ] 에러 핸들링 미흡

### 코멘트
- [필수] `파일:라인` — 설명
- [제안] `파일:라인` — 설명
```

---

## Tester

**책임:**
- 변경된 코드에 대한 테스트 작성
- 기존 테스트 실행 및 결과 보고
- 테스트 커버리지 확인

**입력:** PR diff, 기존 테스트 코드
**출력:** 테스트 코드, 실행 결과 리포트

**사용 명령어:**
```bash
npm test
npm run test:coverage
```

---

## Researcher

**책임:**
- 외부 서비스/제품 벤치마킹 및 기능 비교 분석
- 기술 스택 비교 조사 (라이브러리, 프레임워크, API/SDK)
- 경쟁사 또는 참고 서비스의 구현 방식 분석
- 조사 결과를 구조화된 리포트로 정리

**입력:** 조사 요청 이슈 (조사 목적, 범위, 비교 기준)
**출력:** 조사 리포트 (이슈 코멘트 또는 `docs/research/` 문서)

**워크플로우:**
1. Orchestrator로부터 조사 이슈 할당 받음
2. 조사 범위와 비교 기준 확인
3. 외부 자료 수집 및 분석
4. 구조화된 리포트 작성 → 이슈 코멘트로 제출
5. 필요시 `docs/research/` 에 상세 문서 커밋

**리포트 출력 형식:**
```markdown
## 조사 리포트: [주제]

### 조사 목적
[왜 이 조사가 필요한지]

### 비교 대상
| 항목 | 서비스A | 서비스B | 서비스C |
|------|---------|---------|---------|
| 기능1 | O | O | X |
| 기능2 | X | O | O |
| 라이선스 | MIT | Apache | 상용 |
| 커뮤니티 | 활발 | 보통 | - |

### 분석 요약
[핵심 발견사항 3-5개]

### 권장 사항
[추천 선택지와 근거]
```

**사용 도구:**
- 웹 검색 및 문서 분석
- GitHub 저장소 분석 (`gh repo view`, star/issue 수 등)
- API 문서 확인
