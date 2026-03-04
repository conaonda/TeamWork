#!/bin/bash
# TeamWork 스프린트 자동화 스크립트
# Claude CLI를 루프로 실행하여 매 루프가 하나의 스프린트가 됩니다.
#
# 사용법: ./scripts/sprint.sh --repo owner/repo [--sprints N] [--log-dir ./logs]

set -euo pipefail

# --- 기본값 ---
REPO=""
MAX_SPRINTS=5
LOG_DIR="./sprint-logs"
SPRINT_NUM=1

# --- 인자 파싱 ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --repo)     REPO="$2"; shift 2 ;;
    --sprints)  MAX_SPRINTS="$2"; shift 2 ;;
    --log-dir)  LOG_DIR="$2"; shift 2 ;;
    --start)    SPRINT_NUM="$2"; shift 2 ;;
    *)          echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "Error: --repo 옵션이 필요합니다."
  echo "사용법: ./scripts/sprint.sh --repo owner/repo [--sprints N]"
  exit 1
fi

mkdir -p "$LOG_DIR"

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
  cat <<EOF
당신은 Researcher 에이전트입니다. 저장소: $REPO

다음 작업을 수행하세요:
1. \`gh issue list --repo $REPO --label "agent/researcher" --state open\`으로 조사 이슈를 확인하세요.
2. 조사할 이슈가 없으면 "조사 이슈 없음"이라고 출력하고 종료하세요.
3. 이슈가 있으면 조사 범위와 비교 기준에 따라 외부 서비스/기술을 조사하세요.
4. 구조화된 비교 표와 권장 사항을 이슈 코멘트로 작성하세요.
5. 완료 후 \`agent/researcher\` 라벨을 제거하세요.
EOF
}

developer_prompt() {
  cat <<EOF
당신은 Developer 에이전트입니다. 저장소: $REPO

다음 작업을 수행하세요:
1. \`gh issue list --repo $REPO --label "agent/developer" --state open\`으로 구현 이슈를 확인하세요.
2. 구현할 이슈가 없으면 "구현 이슈 없음"이라고 출력하고 종료하세요.
3. 이슈가 있으면 develop에서 feature/이슈번호-설명 브랜치를 생성하세요.
4. 이슈 요구사항에 따라 구현하세요.
5. 테스트가 통과하는지 확인하세요.
6. 커밋 컨벤션에 따라 커밋하고 PR을 생성하세요 (\`closes #이슈번호\`).
EOF
}

reviewer_prompt() {
  cat <<EOF
당신은 Reviewer 에이전트입니다. 저장소: $REPO

다음 작업을 수행하세요:
1. \`gh pr list --repo $REPO --state open\`으로 리뷰 대기 PR을 확인하세요.
2. 리뷰할 PR이 없으면 "리뷰 PR 없음"이라고 출력하고 종료하세요.
3. PR이 있으면 diff를 분석하세요.
4. 코드리뷰 가이드에 따라 리뷰하고 결과를 제출하세요.
5. 문제가 없으면 승인, 있으면 변경 요청하세요.
EOF
}

tester_prompt() {
  cat <<EOF
당신은 Tester 에이전트입니다. 저장소: $REPO

다음 작업을 수행하세요:
1. 승인된 PR의 변경사항을 확인하세요.
2. 테스트할 PR이 없으면 "테스트 PR 없음"이라고 출력하고 종료하세요.
3. 변경된 코드에 테스트가 충분한지 확인하세요.
4. 부족하면 테스트를 추가하여 PR에 커밋하세요.
5. 전체 테스트를 실행하고 결과를 PR 코멘트로 보고하세요.
EOF
}

orchestrator_end_prompt() {
  cat <<EOF
당신은 Orchestrator 에이전트입니다. 저장소: $REPO

스프린트 $1을 마무리하세요:
1. 승인된 PR을 머지하세요 (\`gh pr merge --squash --delete-branch\`).
2. 완료된 이슈를 확인하세요.
3. 남은 이슈나 새로 발견된 작업이 있으면 이슈로 등록하세요.
4. 스프린트 $1 결과를 요약하세요.
5. 릴리스가 적절하다면 develop→main PR 생성 및 태그를 생성하세요.
EOF
}

# --- 역할 실행 함수 ---
run_agent() {
  local role="$1"
  local prompt="$2"
  local sprint="$3"
  local log_file="$LOG_DIR/sprint-${sprint}-${role}.log"

  echo "  [$role] 실행 중..."
  claude --print "$prompt" > "$log_file" 2>&1 || true
  echo "  [$role] 완료 → $log_file"
}

# --- 메인 루프 ---
echo "========================================="
echo " TeamWork 스프린트 자동화"
echo " 저장소: $REPO"
echo " 스프린트: $SPRINT_NUM ~ $((SPRINT_NUM + MAX_SPRINTS - 1))"
echo "========================================="

for ((i=0; i<MAX_SPRINTS; i++)); do
  current=$((SPRINT_NUM + i))
  echo ""
  echo "----- Sprint $current 시작 -----"

  run_agent "1-orchestrator-start" "$(orchestrator_start_prompt $current)" "$current"
  run_agent "2-researcher"         "$(researcher_prompt)"                  "$current"
  run_agent "3-developer"          "$(developer_prompt)"                   "$current"
  run_agent "4-reviewer"           "$(reviewer_prompt)"                    "$current"
  run_agent "5-tester"             "$(tester_prompt)"                      "$current"
  run_agent "6-orchestrator-end"   "$(orchestrator_end_prompt $current)"   "$current"

  echo "----- Sprint $current 완료 -----"
done

echo ""
echo "========================================="
echo " 전체 스프린트 완료"
echo " 로그: $LOG_DIR/"
echo "========================================="
