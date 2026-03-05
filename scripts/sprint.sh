#!/bin/bash
# TeamWork 스프린트 자동화 스크립트
# Claude CLI를 루프로 실행하여 매 루프가 하나의 스프린트가 됩니다.
#
# 사용법: sprint.sh --repo owner/repo --workdir /path/to/dir [--sprints N] [--start N] [--parallel]

set -euo pipefail

# --- 기본값 ---
REPO=""
WORKDIR=""
MAX_SPRINTS=5
SPRINT_NUM=1
PARALLEL=false
MAX_RETRIES=2

# --- 인자 파싱 ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --repo)      REPO="$2"; shift 2 ;;
    --workdir)   WORKDIR="$2"; shift 2 ;;
    --sprints)   MAX_SPRINTS="$2"; shift 2 ;;
    --start)     SPRINT_NUM="$2"; shift 2 ;;
    --parallel)  PARALLEL=true; shift ;;
    *)           echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "Error: --repo 옵션이 필요합니다."
  echo "사용법: sprint.sh --repo owner/repo --workdir /path/to/dir [--sprints N] [--parallel]"
  exit 1
fi

if [[ -z "$WORKDIR" ]]; then
  echo "Error: --workdir 옵션이 필요합니다."
  echo "사용법: sprint.sh --repo owner/repo --workdir /path/to/dir [--sprints N] [--parallel]"
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

# --- 역할별 허용 도구 ---
TOOLS_ORCHESTRATOR="Bash,Read,Glob,Grep,Write,Edit,mcp__github"
TOOLS_RESEARCHER="Bash,Read,Glob,Grep,WebSearch,WebFetch,mcp__github"
TOOLS_DEVELOPER="Bash,Read,Glob,Grep,Write,Edit,mcp__github"
TOOLS_REVIEWER="Bash,Read,Glob,Grep,mcp__github"
TOOLS_TESTER="Bash,Read,Glob,Grep,Write,Edit,mcp__github"

# .gitignore에 sprint-logs/ 추가
if [[ ! -f .gitignore ]] || ! grep -qx "sprint-logs/" .gitignore 2>/dev/null; then
  echo "sprint-logs/" >> .gitignore
fi

# --- 이전 단계 요약 생성 ---
summarize_log() {
  local log_file="$1"
  if [[ -f "$log_file" ]]; then
    # 마지막 30줄을 요약으로 사용 (핵심 결과가 끝에 있는 경향)
    tail -30 "$log_file" 2>/dev/null || echo "(로그 없음)"
  else
    echo "(이전 단계 로그 없음)"
  fi
}

# --- 역할별 프롬프트 ---
orchestrator_start_prompt() {
  cat <<EOF
당신은 Orchestrator 에이전트입니다. 저장소: $REPO

스프린트 $1을 시작합니다. 다음 작업을 수행하세요:
1. \`gh issue list --repo $REPO --state open --assignee ""\`로 미할당 이슈를 확인하세요.
2. 우선순위를 판단하고 이번 스프린트에서 처리할 이슈를 선택하세요 (최대 3개).
3. 기술 조사가 필요한 이슈는 \`agent/researcher\` 라벨을, 구현 이슈는 \`agent/developer\` 라벨을 지정하세요.
4. 스프린트 계획을 각 이슈 코멘트로 남기세요.

미할당 이슈가 없으면 프로젝트 상태를 분석하고 새 이슈를 생성하세요.
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
EOF
}

tester_prompt() {
  local dev_summary
  dev_summary=$(summarize_log "$LOG_DIR/sprint-${1}-3-developer.log")
  local review_summary
  review_summary=$(summarize_log "$LOG_DIR/sprint-${1}-4-reviewer.log")
  cat <<EOF
당신은 Tester 에이전트입니다. 저장소: $REPO

## 이전 단계 결과 요약:
### Developer:
${dev_summary}
### Reviewer:
${review_summary}

## 작업:
1. 승인된 PR의 변경사항을 확인하세요.
2. 테스트할 PR이 없으면 "테스트 PR 없음"이라고 출력하고 종료하세요.
3. 변경된 코드에 테스트가 충분한지 확인하세요.
4. 부족하면 테스트를 추가하여 PR에 커밋하세요.
5. 전체 테스트를 실행하고 결과를 PR 코멘트로 보고하세요.
EOF
}

orchestrator_end_prompt() {
  local dev_summary
  dev_summary=$(summarize_log "$LOG_DIR/sprint-${1}-3-developer.log")
  local review_summary
  review_summary=$(summarize_log "$LOG_DIR/sprint-${1}-4-reviewer.log")
  local test_summary
  test_summary=$(summarize_log "$LOG_DIR/sprint-${1}-5-tester.log")
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
EOF
}

# --- 역할 실행 함수 (재시도 포함) ---
run_agent() {
  local role="$1"
  local prompt="$2"
  local sprint="$3"
  local model="$4"
  local allowed_tools="${5:-}"
  local log_file="$LOG_DIR/sprint-${sprint}-${role}.log"

  local attempt=0
  while [[ $attempt -le $MAX_RETRIES ]]; do
    if [[ $attempt -gt 0 ]]; then
      echo "  [$role] 재시도 $attempt/$MAX_RETRIES..."
    else
      echo "  [$role] 실행 중... (model: $model)"
    fi

    local tool_args=""
    if [[ -n "$allowed_tools" ]]; then
      tool_args="--allowedTools $allowed_tools"
    fi

    if claude --print --model "$model" $tool_args --dangerously-skip-permissions "$prompt" > "$log_file" 2>&1; then
      echo "  [$role] 완료 → $log_file"
      return 0
    fi

    attempt=$((attempt + 1))
  done

  echo "  [$role] 실패 (${MAX_RETRIES}회 재시도 후) → $log_file"
  return 1
}

# --- 메인 루프 ---
echo "========================================="
echo " TeamWork 스프린트 자동화"
echo " 저장소: $REPO"
echo " 작업 디렉토리: $(pwd)"
echo " 스프린트: $SPRINT_NUM ~ $((SPRINT_NUM + MAX_SPRINTS - 1))"
echo " 병렬 모드: $PARALLEL"
echo " 모델: Orchestrator/Developer=$MODEL_ORCHESTRATOR, Researcher/Reviewer/Tester=$MODEL_RESEARCHER"
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

  echo "----- Sprint $current 시작 -----"

  # 1. Orchestrator 시작
  if ! run_agent "1-orchestrator-start" "$(orchestrator_start_prompt $current)" "$current" "$MODEL_ORCHESTRATOR" "$TOOLS_ORCHESTRATOR"; then
    echo "  [중단] Orchestrator 시작 실패. 스프린트 $current 건너뜀."
    continue
  fi

  # 2+3. Researcher & Developer (병렬 또는 순차)
  if [[ "$PARALLEL" == true ]]; then
    echo "  [병렬] Researcher + Developer 동시 실행"
    run_agent "2-researcher" "$(researcher_prompt $current)" "$current" "$MODEL_RESEARCHER" "$TOOLS_RESEARCHER" &
    PID_RESEARCHER=$!
    run_agent "3-developer" "$(developer_prompt $current)" "$current" "$MODEL_DEVELOPER" "$TOOLS_DEVELOPER" &
    PID_DEVELOPER=$!

    wait $PID_RESEARCHER || echo "  [경고] Researcher 실패"
    if ! wait $PID_DEVELOPER; then
      echo "  [중단] Developer 실패. 스프린트 $current 건너뜀."
      SPRINT_FAILED=true
    fi
  else
    run_agent "2-researcher" "$(researcher_prompt $current)" "$current" "$MODEL_RESEARCHER" "$TOOLS_RESEARCHER" || echo "  [경고] Researcher 실패"
    if ! run_agent "3-developer" "$(developer_prompt $current)" "$current" "$MODEL_DEVELOPER" "$TOOLS_DEVELOPER"; then
      echo "  [중단] Developer 실패. 스프린트 $current 건너뜀."
      SPRINT_FAILED=true
    fi
  fi

  if [[ "$SPRINT_FAILED" == true ]]; then
    continue
  fi

  # 4. Reviewer
  if ! run_agent "4-reviewer" "$(reviewer_prompt $current)" "$current" "$MODEL_REVIEWER" "$TOOLS_REVIEWER"; then
    echo "  [경고] Reviewer 실패. 계속 진행."
  fi

  # 5. Tester
  if ! run_agent "5-tester" "$(tester_prompt $current)" "$current" "$MODEL_TESTER" "$TOOLS_TESTER"; then
    echo "  [경고] Tester 실패. 계속 진행."
  fi

  # 6. Orchestrator 마무리
  if ! run_agent "6-orchestrator-end" "$(orchestrator_end_prompt $current)" "$current" "$MODEL_ORCHESTRATOR" "$TOOLS_ORCHESTRATOR"; then
    echo "  [경고] Orchestrator 마무리 실패."
  fi

  # 스프린트 완료 태그 생성 및 원격 push
  git fetch --tags --quiet 2>/dev/null
  if git tag "sprint-${current}" 2>/dev/null; then
    git push origin "sprint-${current}" 2>/dev/null || \
      echo "  [경고] sprint-${current} 태그 push 실패"
  else
    echo "  [경고] sprint-${current} 태그 생성 실패 (이미 존재할 수 있음)"
  fi

  echo "----- Sprint $current 완료 -----"
done

echo ""
echo "========================================="
echo " 전체 스프린트 완료"
echo " 로그: $(pwd)/$LOG_DIR/"
echo "========================================="
