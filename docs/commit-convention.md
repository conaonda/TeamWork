# 커밋 컨벤션

[Conventional Commits](https://www.conventionalcommits.org/) 기반으로 작성합니다.

## 형식

```
<type>(<scope>): <subject>

<body>
```

## Type
| Type | 설명 |
|------|------|
| `feat` | 새로운 기능 |
| `fix` | 버그 수정 |
| `docs` | 문서 변경 |
| `style` | 코드 포맷팅 (동작 변경 없음) |
| `refactor` | 리팩토링 |
| `test` | 테스트 추가/수정 |
| `chore` | 빌드, 설정 변경 |

## Scope (선택)
변경 범위를 괄호 안에 표기합니다. 예: `feat(auth)`, `fix(api)`

## 규칙
- subject는 50자 이내
- 명령형으로 작성 (예: "추가" O, "추가함" X, "추가했습니다" X)
- 첫 글자 소문자
- 마침표 생략

## 시맨틱 버저닝 연동
커밋 타입에 따라 릴리스 버전이 자동 결정됩니다:

| 커밋 타입 | 버전 변경 | 예시 |
|-----------|-----------|------|
| `fix:` | patch (1.0.x) | 1.0.0 → 1.0.1 |
| `feat:` | minor (1.x.0) | 1.0.1 → 1.1.0 |
| `BREAKING CHANGE` | major (x.0.0) | 1.1.0 → 2.0.0 |

Breaking change는 커밋 body에 `BREAKING CHANGE: 설명`으로 표기합니다.

## 예시
```
feat(auth): 소셜 로그인 추가
fix(api): 사용자 목록 페이지네이션 오류 수정
docs: README 업데이트
refactor(ui): 버튼 컴포넌트 공통화

feat(api)!: 인증 API 엔드포인트 변경

BREAKING CHANGE: /auth/login → /api/v2/auth/login으로 변경
```
