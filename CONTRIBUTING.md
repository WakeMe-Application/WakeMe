# 기여 규칙

## 커밋 메시지

```
TYPE : 타이틀
```

- 본문은 쓰지 않습니다. 배경과 맥락은 **이슈와 PR**에 남깁니다.
- 타이틀은 한국어로, 무엇을 했는지 한 줄로 적습니다.
- `TYPE` 앞뒤로 공백이 들어갑니다 (`FEAT : ...`).

### TYPE

| TYPE | 언제 |
|---|---|
| `FEAT` | 새 기능 |
| `FIX` | 버그 수정 |
| `DATA` | 노선·공공데이터와 변환기 |
| `DESIGN` | 화면·디자인 시스템 |
| `REFACTOR` | 동작은 그대로, 구조만 |
| `TEST` | 테스트 추가·수정 |
| `DOCS` | 문서 |
| `CHORE` | 빌드·설정·자산 |

```
FEAT : 환승 경로 안내 추가
FIX : 급행 매칭이 완행 계통으로 되돌아가지 않던 문제
DATA : 서울교통공사 실측 환승 도보시간 반영
DOCS : 재생 도구 사용법 추가
```

## 브랜치

```
TYPE/짧은-설명
```

`feat/transfer-routing`, `fix/express-rematch` 처럼 소문자로 씁니다. `main` 에 직접 밀지 않습니다.

## 이슈 → PR

1. 이슈를 먼저 엽니다. 템플릿이 형식을 잡아 줍니다.
2. 브랜치를 따고 작업합니다.
3. PR을 열고 본문 마지막에 `Closes #번호` 를 적습니다.
4. PR 템플릿의 **"확인하지 못한 것"** 을 비워 두지 않습니다. 없으면 "없음" 이라고 적습니다.

## 라벨

| 접두 | 뜻 |
|---|---|
| `type:` | 변경 종류. 커밋 TYPE과 같은 이름을 씁니다. |
| `area:` | 어느 부분인지 (`engine` `app` `poc` `data` `infra`) |
| `priority:` | `P0` 놓치면 제품이 성립하지 않음 · `P1` 다음 마일스톤 · `P2` 언젠가 |
| `status:` | `needs-triage` `in-progress` `blocked` |

## 테스트

판정 로직은 OS를 모르는 순수 Swift라 맥에서 바로 돌아갑니다.

```bash
cd Engine && swift test
```

화면을 바꿨다면 시뮬레이터에서 실제로 띄워 보고 PR에 적습니다.

```bash
cd App && xcodegen generate
xcrun simctl launch --terminate-running-process booted com.wakeme.app -uiState trip-alight
```
