<img src="brand/wordmark.png" alt="깨워줘 — 지하철 하차 알림" width="300">

지하철에서 **내릴 역을 놓치지 않게** 깨워 주는 iOS 앱입니다. 방송을 못 들어도, 잠이 들어도 됩니다.

기존 하차 알림 앱들은 문이 열리기 **약 30초 전에 진동 한 번**을 줍니다. 노이즈캔슬링을 끼거나 졸고 있으면 놓치기 쉽고, 혼잡한 차내에서 30초는 문까지 가기에 빠듯합니다. 깨워줘는 **문 열림 60초 이상 전**에 1차 알림을 주고, 도착하면 확인할 때까지 반복합니다.

## 구조

```
App/       iOS 앱 (SwiftUI, iOS 26+) · 위젯 · Live Activity
Engine/    판정 엔진 (Swift Package, Foundation만 의존) + 탑승 로그 재생 도구
PoC/       Phase 0 아이폰 로거와 분석 스크립트
tools/     공공데이터 → 노선 데이터 변환기, 로고 생성기
brand/     아이콘·워드마크
index.html 통합 명세서 (기획서)
```

판정 로직은 OS를 모르는 순수 Swift라 맥에서 `swift test` 로 그대로 돌아갑니다. 앱은 UI와 시스템 연동만 맡습니다.

## 실행

```bash
# 1) 인증키 파일을 만듭니다 (비워 두어도 빌드·동작합니다)
cp App/Support/Secrets.example.xcconfig App/Support/Secrets.xcconfig

# 2) Xcode 프로젝트를 생성합니다 (project.yml 이 원본입니다)
cd App && xcodegen generate && open WakeMe.xcodeproj

# 3) 엔진 테스트
cd Engine && swift test
```

Signing에서 Team을 고르고 Bundle Identifier를 본인 것으로 바꾼 뒤 실행하세요. 자세한 내용은 [App/README.md](App/README.md).

## 인증키

실시간 열차위치 보정은 [서울 열린데이터광장](https://data.seoul.go.kr) 무료 인증키를 씁니다. 키는 저장소에 없습니다.

- `App/Support/Secrets.xcconfig` 에 넣으면 빌드에 주입됩니다 (이 파일은 `.gitignore` 대상입니다)
- 넣지 않아도 앱은 정상 동작하며, **실시간 보정만** 꺼집니다
- 앱 설정 화면에서 직접 넣어 켤 수도 있습니다

## 데이터

노선 데이터(수도권 41개 운행 계통 · 1,134개 역)는 공공데이터에서 생성합니다. 생성물인 `network.json` 을 직접 고치지 말고 [tools/build_network.py](tools/build_network.py) 를 고치세요.

| 출처 | 쓰임 |
|---|---|
| 국토교통부 도시철도 전체노선 | 역 순서 (역번호로는 순서를 만들 수 없습니다) |
| 전국 도시철도 역사정보 표준데이터 (KRIC) | 영문명·좌표·역번호 |
| 서울교통공사 역간 거리·소요시간 (OA-12034) | 구간별 실측 주행시간 |
| 서울교통공사 환승역 거리·소요시간 (OA-13290) | 실측 환승 도보시간 |
| 서울시 실시간 열차위치 API | 탑승 열차 위치 보정 |

## 현재 상태

동작하는 것과 아직 아닌 것을 [App/README.md](App/README.md) 의 "현재 한계" 절에 솔직하게 적어 두었습니다. 요약하면 **위치 판정은 실제 지하철에서 아직 검증되지 않았습니다.** 가속도계 임계값은 추정치이고, [PoC 로거](PoC/README.md)로 탑승 로그를 모아 재생 도구로 맞추는 단계입니다.

## 기여

커밋 메시지는 `TYPE : 타이틀` 한 줄입니다. 자세한 규칙은 [CONTRIBUTING.md](CONTRIBUTING.md).

## 라이선스

Pretendard 글꼴은 SIL Open Font License 1.1 을 따릅니다.
