# 깨워줘 Phase 0 PoC — 아이폰 로거

iOS 우선 전략의 Go/No-go를 판단하기 위한 데이터 수집 도구입니다. (기획서 11장 Phase 0, 가설 H3·H5)

| 경로 | 내용 |
|---|---|
| `WakeMeLogger/` | 아이폰 로거 앱 (SwiftUI, iOS 26+) |
| `analysis/check_ride.py` | 탑승 기록 점검 스크립트 (Python 3) |

## 1. 아이폰에 설치

1. `WakeMeLogger/WakeMeLogger.xcodeproj`를 Xcode로 엽니다.
   - 파일을 추가하거나 설정을 바꿨다면 `WakeMeLogger/`에서 `xcodegen generate`로 다시 생성합니다 (`project.yml`이 원본).
2. 타깃 **WakeMeLogger → Signing & Capabilities**
   - Team: 본인 Apple ID (무료 계정 가능 — 7일마다 재설치 필요)
   - Bundle Identifier: `com.wakeme.logger`는 이미 쓰였을 수 있으니 `com.<본인이름>.thisstop.logger`처럼 바꿉니다.
3. 아이폰을 연결하고 Run. 처음 한 번은 아이폰에서 **설정 > 일반 > VPN 및 기기 관리**에서 개발자를 신뢰하고, **개발자 모드**를 켜야 합니다.
4. 앱을 처음 실행해 위치 권한을 **앱을 사용하는 동안**으로 허용하고, 동작 및 피트니스 권한도 허용합니다.

## 2. 액션 버튼에 "정차 마킹" 지정

**설정 > 동작 버튼 > 단축어 > 깨워줘 로거 · 정차 마킹**

열차가 역에 서서 **문이 열리는 순간** 주머니 속에서 액션 버튼을 누르면 됩니다. 화면을 볼 필요가 없습니다. 이 마크가 역 판별 정확도(H3)를 채점할 **정답 라벨**이 됩니다.

## 3. 탑승 기록 프로토콜

1. 승강장에서 노선·승차역·하차역·방향을 입력하고, 폰 위치와 위치 정확도를 고른 뒤 **기록 시작**을 누릅니다.
2. **바로 잠급니다.** 상단에 파란 위치 표시가 보이면 정상입니다.
3. 역에 정차할 때마다 액션 버튼을 누릅니다. 역이 아닌 곳(터널)에서 서면 앱의 **터널 정차** 버튼을 누릅니다(하차 후 기억나는 대로 메모해도 됩니다).
4. 하차 후 **기록 종료**를 누릅니다.
5. **기록 목록**(오른쪽 위 폴더)에서 파일을 AirDrop으로 Mac에 보냅니다. 파일 앱의 *나의 iPhone > 깨워줘 로거 > rides*에도 있습니다.

실험 조건을 바꿔가며 모아야 비교가 됩니다.

| 변수 | 비교할 값 |
|---|---|
| 위치 정확도 | 1km vs 100m (배터리·생존 차이) |
| 폰 위치 | 주머니 vs 손 (정차 감지 노이즈) |
| 노선 | 2호선 등 다른 노선 1개 이상 |
| 저전력 모드 | 켬 vs 끔 (백그라운드 생존) |

## 4. 점검

```bash
python3 analysis/check_ride.py ride-20260911-183012.jsonl          # 리포트
pip3 install matplotlib                                            # 그래프용 (최초 1회)
python3 analysis/check_ride.py ride-20260911-183012.jsonl --plot   # + PNG 그래프
```

리포트가 판정하는 항목:

| # | 항목 | PASS 기준 |
|---|---|---|
| 1 | 잠금 상태 센서 연속성 | 백그라운드 샘플 수집률 ≥ 95%, 1초 넘는 끊김 0건, 하트비트 공백 없음 |
| 2 | 배터리 소모 | 시간당 ≤ 5% (20분 이상 기록 기준) |
| 3 | 정차 패턴 | 그래프에서 정차 마크(빨간 선) 직전에 감속 봉우리, 정차 중 평탄 구간이 보임 |

**1번이 FAIL이면 iOS 우선 전략을 재검토**해야 합니다. 먼저 저전력 모드를 끄고, 위치 정확도를 100m로 올려 다시 측정합니다.

## 5. 정차 감지 임계값 맞추기 (재생)

`check_ride.py`가 **데이터 품질**(센서가 잠금 상태에서 끊기지 않았는지)을 본다면, 재생 도구는 **알고리즘 품질**을 봅니다. 기록한 로그를 앱에 실제로 들어 있는 `StopDetector`에 그대로 흘려 넣고, 액션 버튼으로 찍은 정답 마크와 맞춰 채점합니다.

```bash
cd ../Engine
swift run ride-replay ~/Downloads/ride-20260914-081203.jsonl           # 현재 기본값으로 채점
swift run ride-replay ~/Downloads/ride-20260914-081203.jsonl --sweep   # 파라미터 격자 120조합 훑기
```

재생은 기본적으로 **앱과 같은 10Hz로 줄여서** 합니다. 로거는 25~50Hz로 기록하지만 앱의 `MotionMonitor`는 10Hz로 돌기 때문에, 기록 속도 그대로 맞춘 임계값은 앱에서 그대로 재현되지 않습니다 — 3초 이동평균에 들어가는 표본이 75개 대 30개라 경계에서 판정이 갈립니다. 기록된 속도 그대로 보려면 `--hz 0`을 줍니다.

읽는 법:

| 항목 | 뜻 | 왜 중요한가 |
|---|---|---|
| 놓침 | 역에 섰는데 감지하지 못함 | 가장 나쁜 실패. 앵커가 갱신되지 않아 알림이 밀린다 |
| 군더더기 | 역도 터널 정차 마크도 없는데 감지 | 앵커가 엉뚱한 곳으로 끌려간다 |
| 평균 오차 | 감지 시각 − 마크 시각 | **음수가 정상**이다. 열차가 선 뒤 문이 열리고 버튼을 누르니까 |
| 표준편차 | 오차가 얼마나 일정한가 | 평균값보다 이게 중요하다. 일정하게 이르면 보정할 수 있지만 들쭉날쭉하면 못 쓴다 |

앱과 재생기는 **같은 코드**를 씁니다. 수평 가속도 변환(`MotionSample.init(time:userAcceleration:gravity:)`)과 판정(`StopDetector`)이 모두 엔진에 있어서, 여기서 고른 값이 그대로 앱에서 도는 값입니다.

한 번의 탑승으로 정하지 마세요. 폰 위치(주머니/손)와 노선을 바꿔 **3회 이상** 모은 뒤, 모든 기록에서 공통으로 놓침이 0에 가까운 조합을 골라 `Engine/Sources/WakeMeEngine/MotionDetector.swift`의 `Parameters` 기본값을 바꿉니다.

## 로그 형식 (JSONL, 한 줄에 레코드 하나)

| type | 필드 | 주기 |
|---|---|---|
| `session_start` | line, from, to, direction, phone_position, location_accuracy, motion_hz, device, os, low_power_mode, battery | 1회 |
| `motion` | ax·ay·az (중력 제거 가속도, g), gx·gy·gz (중력), rx·ry·rz (회전, rad/s) | 25/50Hz |
| `pressure` | kpa, rel_alt_m | 약 1Hz |
| `activity` | automotive, stationary, walking, running, cycling, unknown, confidence | 변화 시 |
| `location` | lat, lon, h_acc, speed | 수신 시 |
| `heartbeat` | samples, hz, max_gap_s, battery, app_state | 10초 |
| `app_state` | state (active / inactive / background) | 변화 시 |
| `mark` | kind (STOP / DEPART / TUNNEL_STOP / NOTE), seq, source, note | 입력 시 |
| `session_end` | reason, motion_samples, max_gap_s | 1회 |

모든 `t`는 Unix 시각(초)입니다. 로그에는 지상 구간 위치가 포함되니 외부에 공유할 때 주의하세요.
