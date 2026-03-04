# 브랜치 전략

## 브랜치 구조

```
main ─────────────────────────── 프로덕션
  └── develop ────────────────── 개발 통합
        ├── feature/xxx ──────── 기능 개발
        ├── fix/xxx ──────────── 버그 수정
        └── hotfix/xxx ───────── 긴급 수정 (main에서 분기)
```

## 브랜치 설명

| 브랜치 | 용도 | 분기 기준 | 머지 대상 |
|--------|------|-----------|-----------|
| `main` | 프로덕션 배포 | - | - |
| `develop` | 개발 통합 | main | main |
| `feature/*` | 기능 개발 | develop | develop |
| `fix/*` | 버그 수정 | develop | develop |
| `hotfix/*` | 긴급 수정 | main | main, develop |

## 규칙
1. `main`과 `develop`에 직접 푸시하지 않습니다.
2. 모든 변경은 PR을 통해 머지합니다.
3. 머지 후 작업 브랜치를 삭제합니다.
4. `hotfix`는 `main`과 `develop` 모두에 머지합니다.

## 네이밍 규칙
```
feature/이슈번호-간단한설명
fix/이슈번호-간단한설명
hotfix/이슈번호-간단한설명
```
예: `feature/42-user-login`, `fix/15-header-overflow`
