#!/bin/bash
# TeamWork 스프린트 자동화 스크립트
# Claude CLI를 루프로 실행하여 매 루프가 하나의 스프린트가 됩니다.
#
# 사용법: sprint.sh --repo owner/repo --workdir /path/to/dir [--sprints N] [--start N] [--parallel] [--research] [--effort high|medium|low]

set -euo pipefail

# --- 기본값 ---
REPO=""
WORKDIR=""
MAX_SPRINTS=5
SPRINT_NUM=1
PARALLEL=false
RESEARCH=false
EFFORT=""
MAX_RETRIES=2
STOP_REQUESTED=false

# --- 인자 파싱 ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --repo)      REPO="$2"; shift 2 ;;
    --workdir)   WORKDIR="$2"; shift 2 ;;
    --sprints)   MAX_SPRINTS="$2"; shift 2 ;;
    --start)     SPRINT_NUM="$2"; shift 2 ;;
    --parallel)  PARALLEL=true; shift ;;
    --research)  RESEARCH=true; shift ;;
    --effort)    EFFORT="$2"; shift 2 ;;
    *)           echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "Error: --repo 옵션이 필요합니다."
  echo "사용법: sprint.sh --repo owner/repo --workdir /path/to/dir [--sprints N] [--parallel] [--research] [--effort high|medium|low]"
  exit 1
fi

if [[ -z "$WORKDIR" ]]; then
  echo "Error: --workdir 옵션이 필요합니다."
  echo "사용법: sprint.sh --repo owner/repo --workdir /path/to/dir [--sprints N] [--parallel] [--research] [--effort high|medium|low]"
  exit 1
fi

# --- 저장소 이름 추출 (owner/repo → repo) ---
REPO_NAME="${REPO##*/}"

# --- 작업 디렉토리 설정 ---
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# 저장소가 없으면 클론
if [[ ! -d "$REPO_NAME" ]]; then
  echo "저장소 클론 중: $REPO → $WORKDIR/$REPO_NAME"
  gh repo clone "$REPO"
fi

cd "$REPO_NAME"

# 로그 디렉토리 생성
LOG_DIR="./sprint-logs"
mkdir -p "$LOG_DIR"

# 시작 번호 자동 결정 (--start 미지정 시 git 태그에서 이어감)
git fetch --tags --quiet 2>/dev/null || echo "[경고] 원격 태그 fetch 실패"
if [[ "$SPRINT_NUM" -eq 1 ]]; then
  LAST=$(git tag -l 'sprint-*' 2>/dev/null \
    | sed 's/sprint-//' | sort -n | tail -1)
  if [[ -n "$LAST" ]]; then
    SPRINT_NUM=$((LAST + 1))
  fi
fi

# --- 역할별 모델 설정 ---
MODEL_ORCHESTRATOR="opus"
MODEL_RESEARCHER="sonnet"
MODEL_DEVELOPER="opus"
MODEL_REVIEWER="sonnet"
MODEL_TESTER="sonnet"
MODEL_DOCUMENTER="sonnet"

# --- 역할별 허용 도구 ---
TOOLS_ORCHESTRATOR="Bash,Read,Glob,Grep,Write,Edit,mcp__github"
TOOLS_RESEARCHER="Bash,Read,Glob,Grep,WebSearch,WebFetch,mcp__github"
TOOLS_DEVELOPER="Bash,Read,Glob,Grep,Write,Edit,mcp__github"
TOOLS_REVIEWER="Bash,Read,Glob,Grep,mcp__github"
TOOLS_TESTER="Bash,Read,Glob,Grep,Write,Edit,mcp__github"
TOOLS_DOCUMENTER="Bash,Read,Glob,Grep,Write,Edit,mcp__github"

# --- 역할별 effort 설정 (budget-tokens) ---
EFFORT_ORCHESTRATOR="low"
EFFORT_RESEARCHER="low"
EFFORT_DEVELOPER="low"
EFFORT_REVIEWER="low"
EFFORT_TESTER="medium"
EFFORT_DOCUMENTER="low"

# .gitignore 설정: 전체 로그는 로컬 전용, 구조화 산출물만 git 추적
_setup_gitignore() {
  local changed=false
  if [[ ! -f .gitignore ]] || ! grep -qx "sprint-logs/" .gitignore 2>/dev/null; then
    echo "sprint-logs/" >> .gitignore
    changed=true
  fi
  # 로그 파일은 로컬 전용 (저장소 비대화 방지)
  if ! grep -qx "sprint-logs/\*.log" .gitignore 2>/dev/null; then
    echo "sprint-logs/*.log" >> .gitignore
    changed=true
  fi
  # 구조화 산출물은 git 추적 예외 처리
  for pattern in "!sprint-logs/*.handoff.json" "!sprint-logs/sprint-memory.md" "!sprint-logs/*-summary.json"; do
    if ! grep -qFx "$pattern" .gitignore 2>/dev/null; then
      echo "$pattern" >> .gitignore
      changed=true
    fi
  done
  [[ "$changed" == true ]] && echo "  [설정] .gitignore 업데이트 완료"
}
_setup_gitignore

# CLAUDE.md 부재 경고
if [[ ! -f "CLAUDE.md" ]]; then
  echo "  [경고] CLAUDE.md 없음 — 에이전트가 프로젝트 컨텍스트를 파악하기 어렵습니다."
  echo "  → TeamWork 저장소의 CLAUDE.md를 참고하여 프로젝트별 CLAUDE.md를 생성하세요."
  echo "  → 계속 진행하려면 Enter, 중단하려면 Ctrl+C"
  read -r || true
fi

# --- 사용량 체크 (Claude Code OAuth API) ---
USAGE_THRESHOLD=80  # 이 퍼센트 이상이면 대기

check_usage() {
  local credentials_file="$HOME/.claude/.credentials.json"
  if [[ ! -f "$credentials_file" ]]; then
    echo "  [사용량] 자격 증명 파일 없음 — 체크 건너뜀"
    return 0
  fi

  local access_token
  access_token=$(python3 -c "
import json, sys
with open('$credentials_file') as f:
    d = json.load(f)
print(d.get('claudeAiOauth', {}).get('accessToken', ''))
" 2>/dev/null)

  if [[ -z "$access_token" ]]; then
    echo "  [사용량] 액세스 토큰 없음 — 체크 건너뜀"
    return 0
  fi

  local response
  response=$(curl -s --max-time 10 \
    -H "Authorization: Bearer $access_token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)

  if [[ -z "$response" ]]; then
    echo "  [사용량] API 응답 없음 — 체크 건너뜀"
    return 0
  fi

  local utilization resets_at
  utilization=$(echo "$response" | python3 -c "
import json, sys
d = json.load(sys.stdin)
u = d.get('five_hour', {}).get('utilization')
print(int(u) if u is not None else '')
" 2>/dev/null)
  resets_at=$(echo "$response" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('five_hour', {}).get('resets_at', ''))
" 2>/dev/null)

  if [[ -z "$utilization" ]]; then
    echo "  [사용량] 사용량 정보 없음 — 체크 건너뜀"
    return 0
  fi

  echo "  [사용량] 5시간 사용량: ${utilization}% (임계값: ${USAGE_THRESHOLD}%)"

  if [[ "$utilization" -ge "$USAGE_THRESHOLD" ]]; then
    if [[ -n "$resets_at" ]]; then
      local reset_epoch now_epoch wait_secs
      reset_epoch=$(date -d "$resets_at" +%s 2>/dev/null || date -jf "%Y-%m-%dT%H:%M:%S" "${resets_at%%.*}" +%s 2>/dev/null)
      now_epoch=$(date +%s)

      if [[ -n "$reset_epoch" && "$reset_epoch" -gt "$now_epoch" ]]; then
        wait_secs=$((reset_epoch - now_epoch + 60))  # 리셋 후 1분 여유
        local wait_min=$((wait_secs / 60))
        echo "  [사용량] 한도 근접 — 리셋 시각: $resets_at"
        echo "  [사용량] ${wait_min}분 대기 중... (ESC로 대기 취소 가능)"

        local elapsed=0
        while [[ $elapsed -lt $wait_secs ]]; do
          sleep 10
          elapsed=$((elapsed + 10))
          check_esc
          if [[ "$STOP_REQUESTED" == true ]]; then
            echo "  [사용량] ESC 감지 — 대기 취소"
            return 1
          fi
          # 5분마다 남은 시간 출력
          if (( elapsed % 300 == 0 )); then
            local remaining=$(( (wait_secs - elapsed) / 60 ))
            echo "  [사용량] 대기 중... 약 ${remaining}분 남음"
          fi
        done
        echo "  [사용량] 대기 완료 — 스프린트 재개"
      fi
    else
      echo "  [사용량] 한도 근접이나 리셋 시각 정보 없음 — 5분 대기"
      sleep 300
    fi
  fi

  return 0
}

# --- 이전 단계 요약 생성 ---
summarize_log() {
  local log_file="$1"
  local handoff_file="${log_file%.log}.handoff.json"

  # 1순위: 핸드오프 JSON (구조화된 정보, 정보 밀도 최고)
  if [[ -f "$handoff_file" ]]; then
    cat "$handoff_file"
    return
  fi

  # 2순위: 폴백 — ANSI 코드 및 claude CLI 노이즈 제거 후 tail
  if [[ -f "$log_file" ]]; then
    sed 's/\x1B\[[0-9;]*[mK]//g' "$log_file" \
      | grep -v '^[[:space:]]*$' \
      | grep -v $'^\s*[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏◐◓◑◒]' \
      | grep -v '^\s*> \(Bash\|Read\|Glob\|Write\|Edit\|Grep\|WebSearch\|WebFetch\)' \
      | tail -40
    return
  fi

  echo "(이전 단계 로그 없음)"
}

# --- 역할별 프롬프트 ---
orchestrator_start_prompt() {
  local memory_file="$LOG_DIR/sprint-memory.md"
  local memory_context=""
  if [[ -f "$memory_file" ]]; then
    memory_context=$(cat "$memory_file")
  fi
  cat <<EOF
당신은 Orchestrator 에이전트입니다. 저장소: $REPO

## 프로젝트 메모리 (이전 스프린트 누적 정보):
${memory_context:-"(첫 스프린트 — 메모리 없음)"}

## 스프린트 $1 시작 작업:
1. \`gh issue list --repo $REPO --state open --assignee ""\`로 미할당 이슈를 확인하세요.
2. 우선순위를 판단하고 이번 스프린트에서 처리할 이슈를 선택하세요 (최대 3개).
3. 기술 조사가 필요한 이슈는 \`agent/researcher\` 라벨을, 구현 이슈는 \`agent/developer\` 라벨을 지정하세요.
4. 스프린트 계획을 각 이슈 코멘트로 남기세요.

미할당 이슈가 없으면 프로젝트 상태를 분석하고 새 이슈를 생성하세요.

## 완료 후 필수 — 핸드오프 파일 생성:
아래 내용으로 \`sprint-logs/sprint-$1-1-orchestrator-start.handoff.json\` 파일을 생성하세요:
\`\`\`json
{
  "role": "orchestrator-start",
  "sprint": $1,
  "status": "success 또는 failure",
  "selected_issues": [{"number": 이슈번호, "title": "이슈제목", "labels": ["라벨"]}],
  "researcher_needed": true 또는 false,
  "issues": ["문제점이나 특이사항"],
  "next_action": "다음 에이전트를 위한 한 줄 요약"
}
\`\`\`
EOF
}

researcher_prompt() {
  local prev_summary
  prev_summary=$(summarize_log "$LOG_DIR/sprint-${1}-1-orchestrator-start.log")
  cat <<EOF
당신은 Researcher 에이전트입니다. 저장소: $REPO

## 이전 단계 (Orchestrator) 결과 요약:
${prev_summary}

## 작업:
1. \`gh issue list --repo $REPO --label "agent/researcher" --state open\`으로 조사 이슈를 확인하세요.
2. 조사할 이슈가 없으면 "조사 이슈 없음"이라고 출력하고 종료하세요.
3. 이슈가 있으면 조사 범위와 비교 기준에 따라 외부 서비스/기술을 조사하세요.
4. 구조화된 비교 표와 권장 사항을 이슈 코멘트로 작성하세요.
5. 완료 후 \`agent/researcher\` 라벨을 제거하세요.

## 완료 후 필수 — 핸드오프 파일 생성:
아래 내용으로 \`sprint-logs/sprint-$1-2-researcher.handoff.json\` 파일을 생성하세요:
\`\`\`json
{
  "role": "researcher",
  "sprint": $1,
  "status": "success, skipped 또는 failure",
  "researched_issues": [이슈번호],
  "key_findings": ["핵심 발견사항 요약"],
  "recommendation": "권장 기술/접근법 한 줄 요약",
  "next_action": "Developer를 위한 한 줄 요약"
}
\`\`\`
EOF
}

developer_prompt() {
  local prev_summary
  prev_summary=$(summarize_log "$LOG_DIR/sprint-${1}-1-orchestrator-start.log")
  local researcher_summary
  researcher_summary=$(summarize_log "$LOG_DIR/sprint-${1}-2-researcher.log")
  cat <<EOF
당신은 Developer 에이전트입니다. 저장소: $REPO

## 이전 단계 결과 요약:
### Orchestrator:
${prev_summary}
### Researcher:
${researcher_summary}

## 작업:
1. \`gh issue list --repo $REPO --label "agent/developer" --state open\`으로 구현 이슈를 확인하세요.
2. 구현할 이슈가 없으면 "구현 이슈 없음"이라고 출력하고 종료하세요.
3. 이슈가 있으면 develop에서 feature/이슈번호-설명 브랜치를 생성하세요.
4. 이슈 요구사항에 따라 구현하세요.
5. 테스트가 통과하는지 확인하세요.
6. 커밋 컨벤션에 따라 커밋하고 PR을 생성하세요 (\`closes #이슈번호\`).

## 완료 후 필수 — 핸드오프 파일 생성:
아래 내용으로 \`sprint-logs/sprint-$1-3-developer.handoff.json\` 파일을 생성하세요:
\`\`\`json
{
  "role": "developer",
  "sprint": $1,
  "status": "success, skipped 또는 failure",
  "completed": ["완료된 이슈 제목 목록"],
  "pr_numbers": [PR번호들],
  "branch_names": ["브랜치명들"],
  "issues": ["발견된 문제점이나 특이사항"],
  "next_action": "Reviewer와 Tester를 위한 한 줄 요약"
}
\`\`\`
EOF
}

reviewer_prompt() {
  local dev_summary
  dev_summary=$(summarize_log "$LOG_DIR/sprint-${1}-3-developer.log")
  cat <<EOF
당신은 Reviewer 에이전트입니다. 저장소: $REPO

## 이전 단계 (Developer) 결과 요약:
${dev_summary}

## 작업:
1. \`gh pr list --repo $REPO --state open\`으로 리뷰 대기 PR을 확인하세요.
2. 리뷰할 PR이 없으면 "리뷰 PR 없음"이라고 출력하고 종료하세요.
3. PR이 있으면 diff를 분석하세요.
4. 코드리뷰 가이드에 따라 리뷰하고 결과를 제출하세요.
5. 문제가 없으면 승인, 있으면 변경 요청하세요.

## 완료 후 필수 — 핸드오프 파일 생성:
아래 내용으로 \`sprint-logs/sprint-$1-4-reviewer.handoff.json\` 파일을 생성하세요:
\`\`\`json
{
  "role": "reviewer",
  "sprint": $1,
  "status": "success, skipped 또는 failure",
  "reviewed_prs": [PR번호들],
  "approved_prs": [승인된 PR번호들],
  "change_requested_prs": [변경요청 PR번호들],
  "issues": ["주요 리뷰 지적사항"],
  "next_action": "Tester를 위한 한 줄 요약"
}
\`\`\`
EOF
}

tester_prompt() {
  local dev_summary
  dev_summary=$(summarize_log "$LOG_DIR/sprint-${1}-3-developer.log")
  # 병렬 모드에서는 reviewer 로그가 없을 수 있으므로 조건부 포함
  local review_context=""
  if [[ "$PARALLEL" != true ]]; then
    local review_summary
    review_summary=$(summarize_log "$LOG_DIR/sprint-${1}-4-reviewer.log")
    review_context="### Reviewer:
${review_summary}"
  fi
  cat <<EOF
당신은 Tester 에이전트입니다. 저장소: $REPO

## 이전 단계 결과 요약:
### Developer:
${dev_summary}
${review_context}

## 작업:
1. \`gh pr list --repo $REPO --state open\`으로 PR의 변경사항을 확인하세요.
2. 테스트할 PR이 없으면 "테스트 PR 없음"이라고 출력하고 종료하세요.
3. 변경된 코드에 테스트가 충분한지 확인하세요.
4. 부족하면 테스트를 추가하여 PR에 커밋하세요.
5. 전체 테스트를 실행하고 결과를 PR 코멘트로 보고하세요.

## 완료 후 필수 — 핸드오프 파일 생성:
아래 내용으로 \`sprint-logs/sprint-$1-5-tester.handoff.json\` 파일을 생성하세요:
\`\`\`json
{
  "role": "tester",
  "sprint": $1,
  "status": "success, skipped 또는 failure",
  "tested_prs": [PR번호들],
  "tests_added": 추가한 테스트 수,
  "total_tests": 전체 테스트 수,
  "all_passed": true 또는 false,
  "issues": ["실패한 테스트나 문제점"],
  "next_action": "Orchestrator를 위한 한 줄 요약"
}
\`\`\`
EOF
}

orchestrator_end_prompt() {
  local dev_summary
  dev_summary=$(summarize_log "$LOG_DIR/sprint-${1}-3-developer.log")
  local review_summary
  review_summary=$(summarize_log "$LOG_DIR/sprint-${1}-4-reviewer.log")
  local test_summary
  test_summary=$(summarize_log "$LOG_DIR/sprint-${1}-5-tester.log")
  local memory_file="$LOG_DIR/sprint-memory.md"
  local memory_context=""
  if [[ -f "$memory_file" ]]; then
    memory_context=$(cat "$memory_file")
  fi
  cat <<EOF
당신은 Orchestrator 에이전트입니다. 저장소: $REPO

## 이전 단계 결과 요약:
### Developer:
${dev_summary}
### Reviewer:
${review_summary}
### Tester:
${test_summary}

## 스프린트 $1 마무리 작업:
1. 승인된 PR을 머지하세요 (\`gh pr merge --squash --delete-branch\`).
2. 완료된 이슈를 확인하세요.
3. 남은 이슈나 새로 발견된 작업이 있으면 이슈로 등록하세요.
4. 스프린트 $1 결과를 요약하세요.
5. 릴리스가 적절하다면 develop→main PR 생성 및 태그를 생성하세요.

## 프로젝트 메모리 업데이트 (sprint-logs/sprint-memory.md):
현재 메모리:
${memory_context:-"(없음 — 새로 생성하세요)"}

sprint-logs/sprint-memory.md 파일을 다음 구조로 업데이트하세요:
\`\`\`markdown
# Sprint Memory — $REPO

## 기술 스택 & 아키텍처 결정
(이번 스프린트에서 새로 결정된 사항 추가, 기존 내용 유지)

## 반복 패턴 & 주의사항
(이번 스프린트에서 발견된 주의사항 추가)

## 기술 부채 목록
(새 항목 추가, 해결된 항목은 [x]로 표시)

## 최근 3개 스프린트 요약
### Sprint $1 ($(date '+%Y-%m-%d'))
- 완료: (머지된 PR과 닫힌 이슈 목록)
- 발견된 문제: (있는 경우)
(이전 스프린트 요약은 최대 2개만 유지)
\`\`\`

## 완료 후 필수 — 핸드오프 파일 생성:
아래 내용으로 \`sprint-logs/sprint-$1-6-orchestrator-end.handoff.json\` 파일을 생성하세요:
\`\`\`json
{
  "role": "orchestrator-end",
  "sprint": $1,
  "status": "success 또는 failure",
  "merged_prs": [머지된 PR번호들],
  "closed_issues": [닫힌 이슈번호들],
  "new_issues_created": [새로 생성된 이슈번호들],
  "released": false 또는 {"version": "vX.Y.Z", "tag": "vX.Y.Z"},
  "next_action": "Documenter를 위한 한 줄 요약"
}
\`\`\`
EOF
}

documenter_prompt() {
  # Orchestrator-end 이후 실행 — 실제 머지된 PR을 대상으로 문서화
  local orch_end_summary
  orch_end_summary=$(summarize_log "$LOG_DIR/sprint-${1}-6-orchestrator-end.log")
  cat <<EOF
당신은 Documenter 에이전트입니다. 저장소: $REPO

## Orchestrator가 완료한 작업 (머지된 PR 정보):
${orch_end_summary}

## 작업:
1. 위 요약에서 머지된 PR 번호를 확인하세요. 머지된 PR이 없으면 "문서화 대상 없음"을 출력하고 종료하세요.
2. \`gh pr view <number> --json files,title,body\`로 각 PR의 변경 파일을 확인하세요.
3. 변경된 코드의 공개 API/인터페이스에 JSDoc/주석 누락이 있으면 추가하세요.
4. README, API 문서, CHANGELOG 등 프로젝트 문서를 갱신하세요.
5. 문서 업데이트가 있으면 \`docs/sprint-$1-update-docs\` 브랜치에서 PR을 생성하세요.
6. 문서 내 링크 유효성을 검증하세요.

## 완료 후 필수 — 핸드오프 파일 생성:
아래 내용으로 \`sprint-logs/sprint-$1-7-documenter.handoff.json\` 파일을 생성하세요:
\`\`\`json
{
  "role": "documenter",
  "sprint": $1,
  "status": "success, skipped 또는 failure",
  "documented_prs": [PR번호들],
  "updated_files": ["갱신된 문서 파일 목록"],
  "doc_pr_number": null 또는 PR번호,
  "issues": ["발견된 문제점"]
}
\`\`\`
EOF
}

# --- 역할 실행 함수 (재시도 포함) ---
run_agent() {
  local role="$1"
  local prompt="$2"
  local sprint="$3"
  local model="$4"
  local allowed_tools="${5:-}"
  local effort="${6:-medium}"
  local log_file="$LOG_DIR/sprint-${sprint}-${role}.log"

  # 글로벌 effort 오버라이드
  if [[ -n "$EFFORT" ]]; then
    effort="$EFFORT"
  fi

  local attempt=0
  while [[ $attempt -le $MAX_RETRIES ]]; do
    if [[ $attempt -gt 0 ]]; then
      echo "  [$role] 재시도 $attempt/$MAX_RETRIES..."
    else
      echo "  [$role] 실행 중... (model: $model, effort: $effort)"
    fi

    local tool_args=""
    if [[ -n "$allowed_tools" ]]; then
      tool_args="--allowedTools $allowed_tools"
    fi

    if claude --print --model "$model" $tool_args --effort "$effort" --dangerously-skip-permissions "$prompt" > "$log_file" 2>&1; then
      if [[ ! -s "$log_file" ]]; then
        echo "  [$role] 경고: 로그 파일이 비어있습니다 — claude CLI 출력 없음"
      else
        echo "  [$role] 완료 → $log_file ($(wc -c < "$log_file") bytes)"
      fi
      return 0
    fi

    attempt=$((attempt + 1))
  done

  echo "  [$role] 실패 (${MAX_RETRIES}회 재시도 후) → $log_file"
  return 1
}

# --- 스프린트 결과 요약 JSON 생성 ---
generate_sprint_summary() {
  local sprint="$1"
  local start_time="$2"
  local end_time
  end_time=$(date +%s)
  local summary_file="$LOG_DIR/sprint-${sprint}-summary.json"

  local start_iso
  start_iso=$(date -d "@$start_time" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null \
    || date -r "$start_time" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null \
    || echo "")

  local closed_issues merged_prs
  closed_issues=$(gh issue list --repo "$REPO" --state closed --limit 20 \
    --json number,title --jq "[.[] | select(.number != null)]" 2>/dev/null || echo "[]")
  merged_prs=$(gh pr list --repo "$REPO" --state merged --limit 20 \
    --json number,title,headRefName --jq "[.[] | select(.number != null)]" 2>/dev/null || echo "[]")

  python3 - <<PYEOF 2>/dev/null || echo "  [경고] sprint summary JSON 생성 실패"
import json
from datetime import datetime

start_time = $start_time
end_time = $end_time
closed_issues = $closed_issues
merged_prs = $merged_prs

summary = {
    "sprint": $sprint,
    "repo": "$REPO",
    "date": datetime.fromtimestamp(start_time).strftime('%Y-%m-%d'),
    "start_time": start_time,
    "end_time": end_time,
    "elapsed_seconds": end_time - start_time,
    "closed_issues": closed_issues,
    "merged_prs": merged_prs,
    "issue_count": len(closed_issues),
    "pr_count": len(merged_prs)
}

with open("$summary_file", "w", encoding="utf-8") as f:
    json.dump(summary, f, ensure_ascii=False, indent=2)
print(f"  [요약] sprint-$sprint-summary.json 생성 완료 ({len(closed_issues)}개 이슈, {len(merged_prs)}개 PR)")
PYEOF
}

# --- ESC 키 감지 (중단 예약) ---
check_esc() {
  local key
  while read -t 0.1 -rsn1 key 2>/dev/null; do
    if [[ "$key" == $'\x1b' ]]; then
      STOP_REQUESTED=true
      echo ""
      echo "  [중단 예약] ESC 감지 — 현재 스프린트 완료 후 종료합니다."
      return
    fi
  done
}

# --- 메인 루프 ---
echo "========================================="
echo " TeamWork 스프린트 자동화"
echo " 저장소: $REPO"
echo " 작업 디렉토리: $(pwd)"
echo " 스프린트: $SPRINT_NUM ~ $((SPRINT_NUM + MAX_SPRINTS - 1))"
echo " 병렬 모드: $PARALLEL"
echo " 리서치 모드: $RESEARCH"
echo " Effort: ${EFFORT:-역할별 기본값}"
echo " 모델: Orchestrator/Developer=$MODEL_ORCHESTRATOR, Researcher/Reviewer/Tester/Documenter=$MODEL_RESEARCHER"
echo "========================================="

for ((i=0; i<MAX_SPRINTS; i++)); do
  current=$((SPRINT_NUM + i))
  SPRINT_FAILED=false
  echo ""

  # 원격 태그 동기화 후 중복 검사
  git fetch --tags --quiet 2>/dev/null
  if git tag -l "sprint-${current}" | grep -q .; then
    echo "  [건너뜀] sprint-${current} 태그가 이미 존재합니다."
    continue
  fi

  # 중단 예약 확인
  if [[ "$STOP_REQUESTED" == true ]]; then
    echo "  [중단] 예약된 중단으로 스프린트 $current 진입을 건너뜁니다."
    break
  fi

  # 사용량 체크 — 한도 근접 시 리셋까지 대기
  if ! check_usage; then
    break
  fi

  SPRINT_START=$(date +%s)
  echo "----- Sprint $current 시작 [$REPO] $(date '+%Y-%m-%d %H:%M:%S') -----"

  # 1. Orchestrator 시작
  if ! run_agent "1-orchestrator-start" "$(orchestrator_start_prompt $current)" "$current" "$MODEL_ORCHESTRATOR" "$TOOLS_ORCHESTRATOR" "$EFFORT_ORCHESTRATOR"; then
    echo "  [중단] Orchestrator 시작 실패. 스프린트 $current 건너뜀."
    continue
  fi

  check_esc

  # 2+3. Researcher (선택) & Developer
  if [[ "$PARALLEL" == true && "$RESEARCH" == true ]]; then
    echo "  [병렬] Researcher + Developer 동시 실행"
    run_agent "2-researcher" "$(researcher_prompt $current)" "$current" "$MODEL_RESEARCHER" "$TOOLS_RESEARCHER" "$EFFORT_RESEARCHER" &
    PID_RESEARCHER=$!
    run_agent "3-developer" "$(developer_prompt $current)" "$current" "$MODEL_DEVELOPER" "$TOOLS_DEVELOPER" "$EFFORT_DEVELOPER" &
    PID_DEVELOPER=$!

    wait $PID_RESEARCHER || echo "  [경고] Researcher 실패"
    if ! wait $PID_DEVELOPER; then
      echo "  [중단] Developer 실패. 스프린트 $current 건너뜀."
      SPRINT_FAILED=true
    fi
  elif [[ "$RESEARCH" == true ]]; then
    run_agent "2-researcher" "$(researcher_prompt $current)" "$current" "$MODEL_RESEARCHER" "$TOOLS_RESEARCHER" "$EFFORT_RESEARCHER" || echo "  [경고] Researcher 실패"
    if ! run_agent "3-developer" "$(developer_prompt $current)" "$current" "$MODEL_DEVELOPER" "$TOOLS_DEVELOPER" "$EFFORT_DEVELOPER"; then
      echo "  [중단] Developer 실패. 스프린트 $current 건너뜀."
      SPRINT_FAILED=true
    fi
  else
    echo "  [건너뜀] Researcher 비활성 (--research 옵션으로 활성화)"
    if ! run_agent "3-developer" "$(developer_prompt $current)" "$current" "$MODEL_DEVELOPER" "$TOOLS_DEVELOPER" "$EFFORT_DEVELOPER"; then
      echo "  [중단] Developer 실패. 스프린트 $current 건너뜀."
      SPRINT_FAILED=true
    fi
  fi

  if [[ "$SPRINT_FAILED" == true ]]; then
    continue
  fi

  check_esc

  # 4. Reviewer + 5. Tester (--parallel 시 동시 실행, 순차 실행 시 Reviewer → Tester)
  if [[ "$PARALLEL" == true ]]; then
    echo "  [병렬] Reviewer + Tester 동시 실행"
    run_agent "4-reviewer" "$(reviewer_prompt $current)" "$current" "$MODEL_REVIEWER" "$TOOLS_REVIEWER" "$EFFORT_REVIEWER" &
    PID_REVIEWER=$!
    run_agent "5-tester" "$(tester_prompt $current)" "$current" "$MODEL_TESTER" "$TOOLS_TESTER" "$EFFORT_TESTER" &
    PID_TESTER=$!
    wait $PID_REVIEWER || echo "  [경고] Reviewer 실패. 계속 진행."
    wait $PID_TESTER   || echo "  [경고] Tester 실패. 계속 진행."
  else
    if ! run_agent "4-reviewer" "$(reviewer_prompt $current)" "$current" "$MODEL_REVIEWER" "$TOOLS_REVIEWER" "$EFFORT_REVIEWER"; then
      echo "  [경고] Reviewer 실패. 계속 진행."
    fi
    check_esc
    if ! run_agent "5-tester" "$(tester_prompt $current)" "$current" "$MODEL_TESTER" "$TOOLS_TESTER" "$EFFORT_TESTER"; then
      echo "  [경고] Tester 실패. 계속 진행."
    fi
  fi

  check_esc

  # 6. Orchestrator 마무리 (PR 머지 포함) — Documenter보다 먼저 실행해야 실제 머지된 PR 참조 가능
  if ! run_agent "6-orchestrator-end" "$(orchestrator_end_prompt $current)" "$current" "$MODEL_ORCHESTRATOR" "$TOOLS_ORCHESTRATOR" "$EFFORT_ORCHESTRATOR"; then
    echo "  [경고] Orchestrator 마무리 실패."
  fi

  check_esc

  # 7. Documenter — Orchestrator-end 이후 실행하여 실제 머지된 PR 기반 문서화
  if ! run_agent "7-documenter" "$(documenter_prompt $current)" "$current" "$MODEL_DOCUMENTER" "$TOOLS_DOCUMENTER" "$EFFORT_DOCUMENTER"; then
    echo "  [경고] Documenter 실패. 계속 진행."
  fi

  # 스프린트 결과 요약 JSON 생성 (구조화 산출물 — git 추적됨)
  generate_sprint_summary "$current" "$SPRINT_START"

  # 스프린트 완료 태그 생성 및 원격 push
  git fetch --tags --quiet 2>/dev/null
  if git tag "sprint-${current}" 2>/dev/null; then
    git push origin "sprint-${current}" 2>/dev/null || \
      echo "  [경고] sprint-${current} 태그 push 실패"
  else
    echo "  [경고] sprint-${current} 태그 생성 실패 (이미 존재할 수 있음)"
  fi

  # 이슈/PR 현황 출력
  echo ""
  echo "  [현황] 이슈:"
  gh issue list --repo "$REPO" --state open --limit 100 --json number 2>/dev/null \
    | jq -r 'length' | xargs -I{} echo "    Open: {}개"
  gh issue list --repo "$REPO" --state closed --search "closed:>=$(date -d '1 hour ago' '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -v-1H '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)" --limit 100 --json number 2>/dev/null \
    | jq -r 'length' | xargs -I{} echo "    이번 스프린트 Closed: {}개"
  echo "  [현황] PR:"
  gh pr list --repo "$REPO" --state open --limit 100 --json number 2>/dev/null \
    | jq -r 'length' | xargs -I{} echo "    Open: {}개"
  gh pr list --repo "$REPO" --state merged --search "merged:>=$(date -d '1 hour ago' '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -v-1H '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)" --limit 100 --json number 2>/dev/null \
    | jq -r 'length' | xargs -I{} echo "    이번 스프린트 Merged: {}개"

  SPRINT_END=$(date +%s)
  ELAPSED=$((SPRINT_END - SPRINT_START))
  ELAPSED_MIN=$((ELAPSED / 60))
  ELAPSED_SEC=$((ELAPSED % 60))
  echo ""
  echo "----- Sprint $current 완료 $(date '+%Y-%m-%d %H:%M:%S') (소요: ${ELAPSED_MIN}분 ${ELAPSED_SEC}초) -----"
done

echo ""
echo "========================================="
echo " 전체 스프린트 완료"
echo " 로그: $(pwd)/$LOG_DIR/"
echo "========================================="
