#!/bin/bash
# TeamWork 저장소 라벨 초기 설정 스크립트
# 사용법: ./scripts/setup-labels.sh [owner/repo]

REPO="${1:-conaonda/TeamWork}"

echo "Setting up labels for $REPO..."

# 기존 기본 라벨 삭제 (선택)
# gh label list --repo "$REPO" --json name -q '.[].name' | xargs -I {} gh label delete {} --repo "$REPO" --yes

# Type 라벨
gh label create "type/bug"       --color "d73a4a" --description "버그 리포트"          --repo "$REPO" --force
gh label create "type/feature"   --color "0075ca" --description "새로운 기능 요청"      --repo "$REPO" --force
gh label create "type/task"      --color "5319e7" --description "일반 태스크"           --repo "$REPO" --force
gh label create "type/refactor"  --color "e4e669" --description "리팩토링"              --repo "$REPO" --force
gh label create "type/docs"      --color "0e8a16" --description "문서 관련"             --repo "$REPO" --force

# Priority 라벨
gh label create "priority/critical" --color "b60205" --description "긴급"             --repo "$REPO" --force
gh label create "priority/high"     --color "d93f0b" --description "높음"             --repo "$REPO" --force
gh label create "priority/medium"   --color "fbca04" --description "보통"             --repo "$REPO" --force
gh label create "priority/low"      --color "c5def5" --description "낮음"             --repo "$REPO" --force

# Status 라벨
gh label create "status/review"     --color "006b75" --description "리뷰 대기"        --repo "$REPO" --force
gh label create "status/blocked"    --color "b60205" --description "블로킹 이슈 있음"  --repo "$REPO" --force
gh label create "status/wontfix"    --color "ffffff" --description "수정하지 않음"     --repo "$REPO" --force

# Agent 라벨
gh label create "agent/developer"  --color "1d76db" --description "Developer 에이전트 담당" --repo "$REPO" --force
gh label create "agent/reviewer"   --color "5319e7" --description "Reviewer 에이전트 담당"  --repo "$REPO" --force
gh label create "agent/tester"     --color "0e8a16" --description "Tester 에이전트 담당"    --repo "$REPO" --force
gh label create "agent/researcher" --color "d4c5f9" --description "Researcher 에이전트 담당" --repo "$REPO" --force
gh label create "agent/documenter" --color "c2e0c6" --description "Documenter 에이전트 담당" --repo "$REPO" --force

# Status 추가
gh label create "status/in-progress" --color "fbca04" --description "작업 진행 중"        --repo "$REPO" --force

echo "Labels setup complete!"
