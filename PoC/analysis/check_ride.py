#!/usr/bin/env python3
"""깨워줘 로거 탑승 기록(JSONL) 점검 — Phase 0 PoC.

퇴근길 1회로 확인할 3가지:
  1. 잠금 상태에서 센서 로그가 끊기지 않았나 (iOS 백그라운드 생존, H5)
  2. 1시간 기준 배터리 소모
  3. 정차 순간의 가속도 패턴이 눈에 보이나 (--plot, matplotlib 필요)

사용법:
  python3 check_ride.py ride-20260911-183012.jsonl
  python3 check_ride.py ride-20260911-183012.jsonl --plot
"""
import argparse
import json
import math
import sys
from collections import Counter
from pathlib import Path

MOTION_GAP_WARN_S = 1.0       # 이보다 긴 모션 공백 = 수집 끊김
HEARTBEAT_GAP_WARN_S = 15.0   # 10초 주기 하트비트가 이보다 벌어짐 = 앱 정지 의심
BACKGROUND_COVERAGE_GOAL = 0.95
BATTERY_GOAL_PER_HOUR = 0.05  # 기획서 9장 초기 목표: 1시간 ≤ 5%
MIN_MINUTES_FOR_BATTERY = 20


def load(path):
    records = []
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                print(f"  ! {n}번째 줄 파싱 실패 (기록 도중 종료돼 잘린 줄일 수 있음)")
    return records


def background_intervals(records, t_end):
    """app_state 기록으로 백그라운드(잠금 포함) 구간 목록을 만든다."""
    intervals, bg_start = [], None
    for r in records:
        if r["type"] != "app_state":
            continue
        if r["state"] == "background" and bg_start is None:
            bg_start = r["t"]
        elif r["state"] != "background" and bg_start is not None:
            intervals.append((bg_start, r["t"]))
            bg_start = None
    if bg_start is not None:
        intervals.append((bg_start, t_end))
    return intervals


def fmt_clock(seconds):
    seconds = max(seconds, 0)
    return f"{int(seconds // 60):d}:{int(seconds % 60):02d}"


def report(records):
    by_type = {}
    for r in records:
        by_type.setdefault(r["type"], []).append(r)

    start = (by_type.get("session_start") or [None])[0]
    if start is None:
        sys.exit("session_start 레코드가 없어요. 깨워줘 로거 파일이 맞나요?")
    t0 = start["t"]
    t_end = max(r["t"] for r in records)
    duration = t_end - t0
    motion_t = [r["t"] for r in by_type.get("motion", [])]
    hz = start.get("motion_hz", 25)

    print(f"\n== 세션: {start.get('line', '')} {start.get('from', '')} → {start.get('to', '')} "
          f"({start.get('direction', '')})")
    print(f"   기기 {start.get('device')} · iOS {start.get('os')} · 폰 위치 {start.get('phone_position')} "
          f"· 위치 정확도 {start.get('location_accuracy')} · 저전력 모드 {start.get('low_power_mode')}")
    print(f"   기록 시간 {fmt_clock(duration)} · 모션 {len(motion_t):,}개 "
          f"(평균 {len(motion_t) / max(duration, 1):.1f}Hz / 설정 {hz}Hz)")
    ended = by_type.get("session_end")
    print(f"   종료: {ended[0]['reason'] if ended else '없음 (앱이 종료됐거나 기록 중 파일)'}")

    # 1. 센서 연속성
    print("\n[1] 잠금 상태 센서 연속성")
    gaps = [(a, b - a) for a, b in zip(motion_t, motion_t[1:]) if b - a > MOTION_GAP_WARN_S]
    for t, gap in gaps[:10]:
        print(f"   ! {fmt_clock(t - t0)} 지점에서 모션 {gap:.1f}초 끊김")
    if len(gaps) > 10:
        print(f"   ! … 외 {len(gaps) - 10}건")

    beats = [r["t"] for r in by_type.get("heartbeat", [])]
    beat_gaps = [(a, b - a) for a, b in zip(beats, beats[1:]) if b - a > HEARTBEAT_GAP_WARN_S]
    for t, gap in beat_gaps[:5]:
        print(f"   ! {fmt_clock(t - t0)} 지점에서 하트비트 {gap:.0f}초 공백 → 앱 정지 의심")

    intervals = background_intervals(records, t_end)
    bg_total = sum(b - a for a, b in intervals)
    if bg_total < 60:
        verdict1 = "재측정 필요"
        print(f"   잠금(백그라운드) 시간이 {bg_total:.0f}초뿐이에요. 잠금 상태로 다시 측정하세요.")
    else:
        bg_samples = sum(1 for t in motion_t if any(a <= t <= b for a, b in intervals))
        coverage = bg_samples / (bg_total * hz)
        ok = coverage >= BACKGROUND_COVERAGE_GOAL and not gaps and not beat_gaps
        verdict1 = "PASS" if ok else "FAIL"
        print(f"   잠금 {fmt_clock(bg_total)} 동안 샘플 수집률 {coverage:.1%} "
              f"(목표 ≥ {BACKGROUND_COVERAGE_GOAL:.0%}) · 1초 넘는 끊김 {len(gaps)}건")
    print(f"   → {verdict1}")

    # 2. 배터리
    print("\n[2] 배터리 소모")
    b0 = start.get("battery", -1)
    b1 = beats and by_type["heartbeat"][-1].get("battery", -1)
    if b0 is None or b0 < 0 or not b1 or b1 < 0:
        verdict2 = "측정 불가"
        print("   배터리 값이 없어요 (시뮬레이터이거나 하트비트 없음)")
    else:
        per_hour = (b0 - b1) / max(duration / 3600, 1e-6)
        verdict2 = "PASS" if per_hour <= BATTERY_GOAL_PER_HOUR else "FAIL"
        print(f"   {b0:.0%} → {b1:.0%} · 시간당 {per_hour:.1%} (목표 ≤ {BATTERY_GOAL_PER_HOUR:.0%})")
        if duration < MIN_MINUTES_FOR_BATTERY * 60:
            verdict2 += " (참고용: 20분 미만 기록)"
    print(f"   → {verdict2}")

    # 마크 요약
    marks = by_type.get("mark", [])
    kinds = Counter(m["kind"] for m in marks)
    print(f"\n[마크] 총 {len(marks)}개 · " + ", ".join(f"{k} {v}" for k, v in kinds.items()))
    stops = [m for m in marks if m["kind"] == "STOP"]
    for a, b in zip(stops, stops[1:]):
        print(f"   정차 #{a['seq']} → #{b['seq']}: {b['t'] - a['t']:.0f}초")

    print("\n[3] 정차 패턴 → --plot 으로 그래프를 확인하세요 (정차 마크 직전에 감속 봉우리가 보이면 OK)")
    return by_type, t0, intervals


def rolling_mean(values, window):
    if window <= 1 or len(values) < window:
        return values
    out, acc = [], 0.0
    for i, v in enumerate(values):
        acc += v
        if i >= window:
            acc -= values[i - window]
        out.append(acc / min(i + 1, window))
    return out


def plot(by_type, t0, intervals, out_path, hz):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("\n그래프: matplotlib이 없어요 → pip3 install matplotlib")
        return

    motion = by_type.get("motion", [])
    t_min, horizontal = [], []
    for r in motion:
        ax, ay, az = r["ax"], r["ay"], r["az"]
        gx, gy, gz = r["gx"], r["gy"], r["gz"]
        g2 = gx * gx + gy * gy + gz * gz or 1.0
        dot = (ax * gx + ay * gy + az * gz) / g2
        hx, hy, hz_ = ax - dot * gx, ay - dot * gy, az - dot * gz  # 중력 방향 성분 제거 = 수평 가속도
        horizontal.append(math.sqrt(hx * hx + hy * hy + hz_ * hz_) * 9.81)
        t_min.append((r["t"] - t0) / 60)
    horizontal = rolling_mean(horizontal, int(hz))

    fig, (ax1, ax2) = plt.subplots(2, 1, sharex=True, figsize=(14, 6), height_ratios=[3, 1])
    ax1.plot(t_min, horizontal, lw=0.7, color="#3B82F6")
    ax1.set_ylabel("horizontal accel (m/s², 1s mean)")
    colors = {"STOP": "#EF4444", "DEPART": "#10B981", "TUNNEL_STOP": "#F59E0B", "NOTE": "#94A3B8"}
    for m in by_type.get("mark", []):
        x = (m["t"] - t0) / 60
        ax1.axvline(x, color=colors.get(m["kind"], "#94A3B8"), lw=1, alpha=0.8)
    for a, b in intervals:
        for axis in (ax1, ax2):
            axis.axvspan((a - t0) / 60, (b - t0) / 60, color="#64748B", alpha=0.08)

    pressure = by_type.get("pressure", [])
    if pressure:
        ax2.plot([(r["t"] - t0) / 60 for r in pressure], [r["kpa"] * 10 for r in pressure],
                 lw=0.8, color="#8B5CF6")
    ax2.set_ylabel("pressure (hPa)")
    ax2.set_xlabel("minutes  (red=STOP, green=DEPART, amber=TUNNEL_STOP, shaded=background)")
    fig.tight_layout()
    fig.savefig(out_path, dpi=120)
    print(f"\n그래프 저장: {out_path}")


def main():
    parser = argparse.ArgumentParser(description="깨워줘 로거 탑승 기록 점검")
    parser.add_argument("file", type=Path)
    parser.add_argument("--plot", action="store_true", help="가속도·기압 그래프 PNG 저장")
    args = parser.parse_args()

    records = load(args.file)
    if not records:
        sys.exit("기록이 비어 있어요.")
    by_type, t0, intervals = report(records)
    if args.plot:
        hz = by_type["session_start"][0].get("motion_hz", 25)
        plot(by_type, t0, intervals, args.file.with_suffix(".png"), hz)


if __name__ == "__main__":
    main()
