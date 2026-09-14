import Foundation
import WakeMeEngine

// PoC 로거가 기록한 탑승 로그(JSONL)를 실제 StopDetector에 재생해 정차 감지를 채점한다.
// 임계값을 책상에서 찍지 않고 실제 탑승 데이터로 정하기 위한 도구다.
//
//   swift run ride-replay ride-20260914-0812.jsonl
//   swift run ride-replay ride-20260914-0812.jsonl --sweep
//
// 정답은 로그의 mark 레코드다. 액션 버튼으로 찍은 STOP이 역 정차,
// TUNNEL_STOP이 역이 아닌 곳에서의 정차다.

// MARK: - 로그 읽기

struct Mark {
    let t: Double
    let kind: String
    let seq: Int
}

struct Ride {
    var title = ""
    var detail = ""
    var samples: [MotionSample] = []
    var marks: [Mark] = []
    var t0: Double = 0
    var t1: Double = 0
    /// 줄이기 전, 로그에 실제로 담긴 표본 수와 속도
    var recordedCount = 0
    var recordedHz = 0.0

    var stops: [Mark] { marks.filter { $0.kind == "STOP" } }
    var tunnels: [Mark] { marks.filter { $0.kind == "TUNNEL_STOP" } }
    var hz: Double { samples.count > 1 ? Double(samples.count) / max(t1 - t0, 0.001) : 0 }
}

func load(_ path: String) -> Ride {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        fail("파일을 읽을 수 없습니다: \(path)")
    }
    var ride = Ride()
    var times: [Double] = []

    for line in text.split(separator: "\n") {
        guard let data = line.data(using: .utf8),
              let row = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = row["type"] as? String,
              let t = row["t"] as? Double
        else { continue }

        times.append(t)
        switch type {
        case "motion":
            guard let ax = row["ax"] as? Double, let ay = row["ay"] as? Double, let az = row["az"] as? Double,
                  let gx = row["gx"] as? Double, let gy = row["gy"] as? Double, let gz = row["gz"] as? Double
            else { continue }
            // 앱과 같은 변환을 쓴다 — 엔진의 이니셜라이저
            ride.samples.append(MotionSample(
                time: Date(timeIntervalSince1970: t),
                userAcceleration: (ax, ay, az),
                gravity: (gx, gy, gz)))
        case "mark":
            guard let kind = row["kind"] as? String else { continue }
            ride.marks.append(Mark(t: t, kind: kind, seq: (row["seq"] as? Int) ?? 0))
        case "session_start":
            let line = (row["line"] as? String) ?? ""
            let from = (row["from"] as? String) ?? ""
            let to = (row["to"] as? String) ?? ""
            let direction = (row["direction"] as? String) ?? ""
            ride.title = "\(line) \(from) → \(to) \(direction)".trimmingCharacters(in: .whitespaces)
            ride.detail = [
                (row["phone_position"] as? String).map { "폰 \($0)" },
                (row["device"] as? String),
                (row["low_power_mode"] as? Bool).map { $0 ? "저전력 켬" : "저전력 끔" },
            ].compactMap { $0 }.joined(separator: " · ")
        default:
            break
        }
    }

    guard !ride.samples.isEmpty else { fail("motion 레코드가 없습니다. 로거가 만든 파일이 맞나요?") }
    ride.t0 = times.min() ?? 0
    ride.t1 = times.max() ?? 0
    ride.recordedCount = ride.samples.count
    ride.recordedHz = ride.hz
    return ride
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// 앱의 `MotionMonitor`는 10Hz로 돈다. 로거는 25~50Hz로 기록하므로 그대로 재생하면
/// 이동평균에 들어가는 표본 수가 달라져(3초 창에 75개 대 30개) 경계에서 판정이 갈린다.
/// 그래서 기본값은 앱과 같은 속도로 줄여 재생하는 것이다.
func downsample(_ samples: [MotionSample], hz: Double) -> [MotionSample] {
    guard hz > 0, let first = samples.first else { return samples }
    let step = 1.0 / hz
    var result = [first]
    var next = first.time.timeIntervalSince1970 + step
    for sample in samples.dropFirst() {
        let t = sample.time.timeIntervalSince1970
        guard t + 1e-9 >= next else { continue }
        result.append(sample)
        next += step
        // 기록이 끊겼던 구간 뒤에서는 다시 맞춘다 (매번 맞추면 요청보다 느려진다)
        if t > next + step { next = t + step }
    }
    return result
}

// MARK: - 재생과 채점

/// 감지된 정차 시각을 정답 마크에 붙여 본 결과
struct Score {
    /// (정답 마크, 감지 시각 - 마크 시각). 음수면 마크보다 먼저 감지한 것.
    var matched: [(mark: Mark, offset: Double)] = []
    var missed: [Mark] = []
    /// 역도 아니고 터널 정차 마크도 없는데 감지한 것
    var extra: [Double] = []
    /// 터널 정차 마크에 붙은 감지 (감지 자체는 맞지만 역으로 쓰면 안 되는 것)
    var tunnel = 0

    var offsets: [Double] { matched.map(\.offset) }
    var meanOffset: Double { offsets.isEmpty ? 0 : offsets.reduce(0, +) / Double(offsets.count) }
    var stdev: Double {
        guard offsets.count > 1 else { return 0 }
        let m = meanOffset
        return (offsets.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(offsets.count - 1)).squareRoot()
    }
}

/// 마크와 감지를 같은 것으로 볼 시간 범위 (초).
/// 액션 버튼은 문이 열린 뒤 눌리므로 감지가 마크보다 조금 이른 것이 정상이다.
let matchWindow: Double = 45

func replay(_ ride: Ride, _ parameters: StopDetector.Parameters) -> [Double] {
    var detector = StopDetector(parameters: parameters)
    var stops: [Double] = []
    for sample in ride.samples {
        if case .stopped(let at)? = detector.consume(sample) {
            stops.append(at.timeIntervalSince1970)
        }
    }
    return stops
}

func score(_ ride: Ride, _ detected: [Double]) -> Score {
    var result = Score()
    var used = Set<Int>()

    for mark in ride.stops {
        let candidates = detected.enumerated()
            .filter { !used.contains($0.offset) && abs($0.element - mark.t) <= matchWindow }
        if let best = candidates.min(by: { abs($0.element - mark.t) < abs($1.element - mark.t) }) {
            used.insert(best.offset)
            result.matched.append((mark, best.element - mark.t))
        } else {
            result.missed.append(mark)
        }
    }

    for (index, stop) in detected.enumerated() where !used.contains(index) {
        if ride.tunnels.contains(where: { abs($0.t - stop) <= matchWindow }) {
            result.tunnel += 1
        } else {
            result.extra.append(stop)
        }
    }
    return result
}

// MARK: - 출력

func clock(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    return String(format: "%02d:%02d", total / 60, total % 60)
}

func printReport(_ ride: Ride, _ parameters: StopDetector.Parameters) {
    let detected = replay(ride, parameters)
    let result = score(ride, detected)

    print("\n== 재생: \(ride.title.isEmpty ? "(제목 없음)" : ride.title)")
    if !ride.detail.isEmpty { print("   \(ride.detail)") }
    print(String(format: "   기록 모션 %d개 · %.1fHz · %@",
                 ride.recordedCount, ride.recordedHz, clock(ride.t1 - ride.t0)))
    let note = replayHz <= 0 ? "기록된 속도 그대로"
        : abs(replayHz - 10) < 0.01 ? "앱의 MotionMonitor와 같은 속도" : "직접 지정"
    print(String(format: "   재생 표본 %d개 · %.1fHz (%@)",
                 ride.samples.count, ride.hz, note))
    print("   정답 마크: 역 정차 \(ride.stops.count) · 터널 정차 \(ride.tunnels.count)")
    print(String(format: "   파라미터: 조용함 %.2f m/s² · %.0f초 지속 · 이동평균 %.0f초 · 출발 %.0f초",
                 parameters.quietThreshold, parameters.quietDuration,
                 parameters.window, parameters.movingDuration))

    print("\n[감지] 정차 \(detected.count)회")
    for (mark, offset) in result.matched {
        print(String(format: "   역 #%d %@ → 감지 %@ (%+.1f초)",
                     mark.seq, clock(mark.t - ride.t0),
                     clock(mark.t + offset - ride.t0), offset))
    }
    for mark in result.missed {
        print("   놓침: 역 #\(mark.seq) \(clock(mark.t - ride.t0))")
    }
    for stop in result.extra {
        print("   군더더기: \(clock(stop - ride.t0)) (마크 없음)")
    }
    if result.tunnel > 0 {
        print("   터널 정차 \(result.tunnel)회 감지 — 감지는 맞지만 역으로 세면 안 되는 것")
    }

    let total = ride.stops.count
    let rate = total > 0 ? Double(result.matched.count) / Double(total) : 0
    print(String(format: "\n[점수] %d역 중 %d 감지 (%.0f%%) · 오검출 %d · 평균 오차 %+.1f초 (표준편차 %.1f)",
                 total, result.matched.count, rate * 100, result.extra.count,
                 result.meanOffset, result.stdev))
    if result.meanOffset < -20 {
        print("   감지가 마크보다 한참 이릅니다. 정상입니다 — 열차가 선 뒤 문이 열리고 버튼을 누르니까요.")
    }
}

/// 파라미터 격자를 훑어 어떤 조합이 이 로그를 가장 잘 맞히는지 본다
func printSweep(_ ride: Ride) {
    struct Row {
        let p: StopDetector.Parameters
        let s: Score
        let detected: Int
    }
    var rows: [Row] = []
    for threshold in [0.15, 0.20, 0.25, 0.30, 0.35, 0.45] {
        for quiet in [4.0, 6.0, 8.0, 10.0, 12.0] {
            for window in [2.0, 3.0, 4.0, 5.0] {
                let p = StopDetector.Parameters(
                    quietThreshold: threshold, quietDuration: quiet,
                    movingDuration: 4, window: window)
                let detected = replay(ride, p)
                rows.append(Row(p: p, s: score(ride, detected), detected: detected.count))
            }
        }
    }
    // 놓친 역이 적은 것 → 오검출이 적은 것 → 오차가 일정한 것(표준편차) 순
    rows.sort {
        ($0.s.missed.count, $0.s.extra.count, $0.s.stdev)
            < ($1.s.missed.count, $1.s.extra.count, $1.s.stdev)
    }

    print("\n== 파라미터 훑기 (\(rows.count)개 조합, 상위 12개)")
    print("   조용함  지속  평균창 │ 감지  맞힘  놓침  오검출 │ 평균오차  표준편차")
    for row in rows.prefix(12) {
        print(String(format: "   %5.2f  %4.0f  %5.0f │ %4d  %4d  %4d  %6d │ %+7.1f  %8.1f",
                     row.p.quietThreshold, row.p.quietDuration, row.p.window,
                     row.detected, row.s.matched.count, row.s.missed.count, row.s.extra.count,
                     row.s.meanOffset, row.s.stdev))
    }
    print("\n   현재 기본값: 조용함 0.25 · 지속 8 · 평균창 3")
    print("   한 번의 탑승으로 정하지 마세요. 서로 다른 노선·폰 위치로 3회 이상 모아 공통으로 좋은 값을 고릅니다.")
}

// MARK: - 진입점

let arguments = Array(CommandLine.arguments.dropFirst())
guard let path = arguments.first(where: { !$0.hasPrefix("--") }) else {
    fail("""
    사용법: swift run ride-replay <ride.jsonl> [--sweep] [--hz N]

      <ride.jsonl>  PoC 로거가 만든 탑승 기록
      --sweep       파라미터 격자를 훑어 이 기록에 가장 맞는 조합을 찾는다
      --hz N        재생 속도 (기본 10 — 앱과 같다. 0을 주면 기록된 속도 그대로)
    """)
}

let replayHz: Double = {
    guard let index = arguments.firstIndex(of: "--hz"),
          index + 1 < arguments.count,
          let value = Double(arguments[index + 1])
    else { return 10 }
    return value
}()

var ride = load(path)
ride.samples = downsample(ride.samples, hz: replayHz)
printReport(ride, StopDetector.Parameters())
if arguments.contains("--sweep") { printSweep(ride) }
