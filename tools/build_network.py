#!/usr/bin/env python3
"""공공데이터 → 깨워줘 노선 데이터(network.json) 생성기.

두 데이터를 합친다.
  1) 순서: 국토교통부_도시철도 전체노선 (CSV, 순번 컬럼)
     https://www.data.go.kr/data/15122916/fileData.do
  2) 속성: 전국 도시철도 역사정보 표준데이터 (XLSX, 영문명·환승·좌표·역번호)
     https://data.kric.go.kr/rips/M_01_01/detail.do?id=32
선택으로 서울교통공사 실측 두 가지를 더 합친다.
  3) 역간 소요시간 (OA-12034) → 구간별 주행 시간
  4) 환승역 거리·소요시간 (OA-13290) → 환승 도보 시간

역번호만으로는 순서를 만들 수 없다. 나중에 생긴 역이 번호 끝에 붙기 때문이다
(예: 경부선 독산 1714가 수원 1713 뒤). 그래서 순서는 반드시 국토부 순번을 쓴다.

사용법:
  python3 tools/build_network.py --order order.csv --master stations.xlsx \
      --timing timing.csv --transfers transfer.csv \
      --out Engine/Sources/WakeMeEngine/Resources/network.json
"""
import argparse
import csv
import json
import re
import sys
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path

RUN_SECONDS = 95.0
DWELL_SECONDS = 30.0

# 표시 순서대로. short는 노선 배지 문구.
LINES = [
    # (국토부 노선명, id, 표시 이름, short, 색)
    ("1호선", "L1", "1호선", "1", "#0052A4"),
    ("2호선", "L2", "2호선", "2", "#00A84D"),
    ("3호선", "L3", "3호선", "3", "#EF7C1C"),
    ("4호선", "L4", "4호선", "4", "#00A5DE"),
    ("5호선", "L5", "5호선", "5", "#996CAC"),
    ("6호선", "L6", "6호선", "6", "#CD7C2F"),
    ("7호선", "L7", "7호선", "7", "#747F00"),
    ("8호선", "L8", "8호선", "8", "#E6186C"),
    ("9호선", "L9", "9호선", "9", "#BDB092"),
    ("경의중앙", "KG", "경의중앙선", "경의", "#77C4A3"),
    ("수인분당", "SB", "수인분당선", "수인", "#F5A200"),
    ("신분당", "SIN", "신분당선", "신분", "#D4003B"),
    ("공항", "AREX", "공항철도", "공항", "#0090D2"),
    ("경춘", "GC", "경춘선", "경춘", "#0C8E72"),
    ("경강", "GG", "경강선", "경강", "#003DA5"),
    ("서해선", "SH", "서해선", "서해", "#81A914"),
    ("GTX-A", "GTXA", "GTX-A", "A", "#9A6292"),
    ("인천1호선", "I1", "인천 1호선", "인1", "#7CA8D5"),
    ("인천2호선", "I2", "인천 2호선", "인2", "#ED8B00"),
    ("김포골드라인", "GIMPO", "김포골드라인", "김포", "#A17E46"),
    ("신림선", "SILLIM", "신림선", "신림", "#6789CA"),
    ("우이신설", "UI", "우이신설선", "우이", "#B0CE18"),
    ("에버라인", "EVER", "에버라인", "에버", "#509F22"),
    ("의정부", "UIJB", "의정부경전철", "의정", "#FDA600"),
]

# 같은 역 이름이 여러 노선·도시에 있으므로, 역번호는 이 노선에 해당하는 행에서만 가져온다.
LINE_MASTER = {
    "1호선": {"1호선", "경부선", "경인선", "경원선", "장항선"},
    "2호선": {"2호선"},
    "3호선": {"3호선", "일산선"},
    "4호선": {"4호선", "안산과천선", "진접선"},
    "5호선": {"5호선"},
    "6호선": {"6호선"},
    "7호선": {"7호선", "도시철도 7호선"},
    "8호선": {"8호선", "수도권 광역철도 8호선"},
    "9호선": {"서울 도시철도 9호선", "수도권  도시철도 9호선"},
    "경의중앙": {"경의중앙선"},
    "수인분당": {"분당선", "수인선"},
    "신분당": {"신분당선"},
    "공항": {"인천국제공항선"},
    "경춘": {"경춘선"},
    "경강": {"경강선"},
    "서해선": {"서해선"},
    "인천1호선": {"인천지하철 1호선"},
    "인천2호선": {"인천지하철 2호선"},
    "김포골드라인": {"김포도시철도"},
    "신림선": {"수도권 경량도시철도 신림선"},
    "우이신설": {"우이신설선"},
    "에버라인": {"에버라인"},
    "의정부": {"의정부"},
}

# 수도권이 아닌 도시의 같은 이름 역 (부산 시청·교대 등)을 걸러낸다
NON_METRO = ("부산", "대구", "광주", "대전", "김해", "동해", "대경")

# 국토부 순번이 원하는 정방향과 반대인 노선
REVERSED = {"2호선"}
# 순환선을 이 역에서 시작하도록 회전
START_AT = {"2호선": "시청"}

# 지선 정의: (이름, 방식, 분기역, 소속)
#   fork    분기역까지의 본선 + 자기 구간 (예: 1호선 인천행, 5호선 마천행)
#   spur    분기역 + 자기 구간만 (예: 2호선 성수지선)
#   segment 자기 구간만 (미개통 구간이 사이에 있는 GTX-A)
# 소속은 역 이름 목록이거나, 표준데이터의 노선명(그 노선 소속 역 전체)이다.
BRANCHES = {
    "1호선": [
        ("인천", "fork", "구로", ["경인선"]),
        ("신창", "fork", "구로", ["경부선", "장항선"]),
        ("광명", "spur", "금천구청", ["광명"]),
        ("서동탄", "spur", "병점", ["서동탄"]),
    ],
    "2호선": [
        ("성수지선", "spur", "성수", ["용답", "신답", "용두", "신설동"]),
        ("신정지선", "spur", "신도림", ["도림천", "양천구청", "신정네거리", "까치산"]),
    ],
    "5호선": [
        ("마천", "fork", "강동", ["둔촌동", "올림픽공원", "방이", "오금", "개롱", "거여", "마천"]),
    ],
    "경의중앙": [
        ("서울역", "fork", "가좌", ["신촌", "서울"]),
    ],
    "GTX-A": [
        ("수서~동탄", "segment", None, ["수서", "성남", "구성", "동탄"]),
        ("운정중앙~서울역", "segment", None, ["서울역", "연신내", "대곡", "킨텍스", "운정중앙"]),
    ],
}

# 본선을 따로 내보내지 않는 노선 (본선만으로는 운행 계통이 아님)
NO_MAIN = {"1호선", "GTX-A"}
# 본선 이름 (지선이 있는 노선만)
MAIN_BRANCH = {"5호선": "하남검단산"}

CIRCULAR = {"L2-본선"}
DIRECTION_OVERRIDE = {"L2-본선": ("내선순환", "외선순환")}

# 국토부 파일에 빠진 역 (표준데이터에는 있음). (기준역, [뒤에 넣을 역]) — 기준역 None이면 맨 앞.
INSERTS = {
    "인천1호선": [(None, ["검단호수공원", "신검단중앙", "아라"])],
    "서해선": [("김포공항역", ["원종"])],
}

# 급행은 통과역 정차를 건너뛸 뿐 아니라 표정속도 자체가 빠르다.
# 전용 급행선로를 쓰는 9호선이 가장 빠르고, 완행선을 함께 쓰는 코레일 급행은 차이가 작다.
# 실측 시각표를 넣으면 이 값은 필요 없어진다.
EXPRESS_SPEEDUP = {"9호선": 0.75, "기본": 0.9}

# 급행 계통. 정차역은 위키백과 노선 문서(경인선·1호선·경의중앙선·수인분당선)에서 옮겼다.
# "..."은 앞뒤 정차역 사이를 각역정차한다는 뜻이다. (계통 이름, 기준 계통, 정차역)
EXPRESS = {
    "9호선": [("급행", "본선", [
        "김포공항", "마곡나루", "가양", "염창", "당산", "여의도", "노량진", "동작",
        "고속터미널", "신논현", "선정릉", "봉은사", "종합운동장", "석촌", "올림픽공원", "중앙보훈병원",
    ])],
    "1호선": [
        # 경인선 급행: 구로~용산은 각역정차 (경인선 문서 "운영")
        ("경인급행", "인천", [
            "용산", "...", "구로", "개봉", "역곡", "부천", "송내", "부평", "동암", "주안", "제물포", "동인천",
        ]),
        # 경원선 급행: 광운대~인천은 각역정차, 평일 출근시간대 운행
        ("경원급행", "인천", [
            "인천", "...", "광운대", "창동", "도봉산", "회룡", "의정부", "양주", "덕정", "지행",
            "동두천중앙", "동두천",
        ]),
        # 경부선 급행: 청량리~가산디지털단지와 천안~신창은 각역정차.
        # 일부 열차만 서는 의왕·금천구청은 뺐다.
        ("경부급행", "신창", [
            "청량리", "...", "가산디지털단지", "안양", "금정", "성균관대", "수원", "병점", "오산",
            "서정리", "평택", "성환", "두정", "천안", "...", "신창",
        ]),
    ],
    "경의중앙": [
        ("경의선급행", "본선", [
            "문산", "금촌", "금릉", "운정", "탄현", "일산", "백마", "대곡", "행신",
            "디지털미디어시티", "홍대입구", "공덕", "용산", "...", "지평",
        ]),
        ("중앙선급행", "본선", [
            "용산", "이촌", "옥수", "왕십리", "청량리", "회기", "상봉", "구리", "도농", "덕소",
            "도심", "양수", "양평", "용문",
        ]),
        ("서울역급행", "서울역", [
            "문산", "금촌", "운정", "일산", "백마", "대곡", "행신", "디지털미디어시티", "가좌", "신촌", "서울역",
        ]),
    ],
    "수인분당": [
        ("분당선급행", "본선", ["왕십리", "...", "죽전", "기흥", "망포", "수원시청", "수원", "고색"]),
        ("수인선급행", "본선", ["오이도", "소래포구", "인천논현", "원인재", "연수", "인하대", "인천"]),
    ],
}

# 두 데이터의 역명 표기 차이
ALIASES = {
    "능길": "신길온천",
    "춘천(한림대)": "춘천",
    "당고개": "불암산",
}

# 환승 데이터와 우리 표기의 차이
TRANSFER_LINE_ALIASES = {"국철": "1호선", "경원선": "1호선", "인천1호선": "인천 1호선"}
TRANSFER_STATION_ALIASES = {"이수": "총신대입구"}

# 표준데이터에 없는 역(신설·비운영)의 영문명
ENGLISH_FALLBACK = {
    "도라산": "Dorasan",
    "동탄": "Dongtan",
    "킨텍스": "KINTEX",
    "운정중앙": "Unjeong Jungang",
    "운동장·송담대": "Stadium·Songdam College",
}


def normalize(name: str) -> str:
    """비교용 이름: 괄호 설명과 끝의 '역'을 떼고 구두점을 통일한다."""
    name = unicodedata.normalize("NFC", name).strip()
    name = re.sub(r"[（(].*?[)）]", "", name).strip()
    name = name.replace(".", "·").replace(" ", "")
    if name.endswith("역") and len(name) > 2:
        name = name[:-1]
    return ALIASES.get(name, name)


def load_master(path: Path):
    """표준데이터(XLSX) → ({정규화 역명: [행]}, {노선명: {정규화 역명}})"""
    import openpyxl

    wb = openpyxl.load_workbook(path, read_only=True)
    ws = wb[wb.sheetnames[0]]
    rows = list(ws.iter_rows(values_only=True))
    head = [str(c).strip() for c in rows[0]]
    master, by_line = defaultdict(list), defaultdict(set)
    for raw in rows[1:]:
        if not raw or not raw[1]:
            continue
        row = {h: ("" if v is None else str(v).strip()) for h, v in zip(head, raw)}
        key = normalize(row["역사명"])
        master[key].append(row)
        by_line[row["노선명"]].add(key)
    return master, by_line


def load_order(path: Path):
    """국토부 순서 CSV → {노선명: [역명, ...]} (순번 정렬, 빠진 역 보완)"""
    raw = defaultdict(list)
    with path.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["권역명"] == "수도권":
                raw[row["노선명"]].append((int(row["순번"]), row["역명"]))

    order = {}
    for line, items in raw.items():
        names, seen = [], set()
        for _, name in sorted(items, key=lambda t: t[0]):
            if normalize(name) not in seen:
                seen.add(normalize(name))
                names.append(name)
        for anchor, extras in INSERTS.get(line, []):
            at = 0 if anchor is None else next(
                (i + 1 for i, n in enumerate(names) if normalize(n) == normalize(anchor)), len(names))
            names[at:at] = extras
        if line in REVERSED:
            names.reverse()
        if line in START_AT:
            start = next((i for i, n in enumerate(names) if normalize(n) == normalize(START_AT[line])), 0)
            names = names[start:] + names[:start]
        order[line] = names

    # 같은 역이 노선마다 다르게 적혀 있다 (청량리 / 청량리(서울시립대입구)).
    # 그대로 두면 환승역이 따로 묶이므로 가장 짧은 표기로 통일한다.
    canonical = {}
    for names in order.values():
        for name in names:
            key = normalize(name)
            if key not in canonical or len(name) < len(canonical[key]):
                canonical[key] = name
    for line, names in order.items():
        order[line] = [canonical[normalize(n)] for n in names]
    return order


def load_timing(path):
    """서울교통공사 역간 거리·소요시간 CSV → {(호선, 이전역, 다음역): 초}. 양방향으로 넣는다.

    출처: 서울 열린데이터광장 OA-12034 (1~8호선, 서울교통공사 운영 구간만).
    '소요시간'은 앞 역을 출발해 이 역에 도착하기까지의 표준 주행시간(mm:ss)이다.
    """
    if path is None:
        return {}
    timing, previous_line, previous_name = {}, None, None
    with path.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            line = row["호선"].strip()
            name = normalize(row["역명"])
            raw = (row.get("소요시간") or row.get("운행시간") or "").strip()
            parts = [int(p) for p in raw.split(":")] if ":" in raw else []
            seconds = parts[0] * 60 + parts[1] if len(parts) == 2 else 0
            if line == previous_line and previous_name and seconds > 0:
                timing[(line, previous_name, name)] = float(seconds)
                timing[(line, name, previous_name)] = float(seconds)
            previous_line, previous_name = line, name
    return timing


def load_transfers(path, station_names, line_names, report):
    """서울교통공사 환승역거리·소요시간 CSV → 양방향 환승 도보시간.

    출처: 서울 열린데이터광장 OA-13290 (1~9호선 환승역).
    '환승소요시간'은 보행속도 1.2m/s 기준 **도보 시간**이라 열차 대기는 빠져 있다.
    """
    if path is None:
        return []

    def seconds(text):
        match = re.match(r"(?:(\d+)\s*분)?\s*(\d+)?\s*초?", text.strip())
        return int(match.group(1) or 0) * 60 + int(match.group(2) or 0) if match else 0

    result, seen = [], set()
    with path.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            raw_station = row["환승역명"].strip()
            station = station_names.get(normalize(TRANSFER_STATION_ALIASES.get(raw_station, raw_station)))
            here = f"{row['호선'].strip()}호선"
            there = row["환승노선"].strip()
            there = TRANSFER_LINE_ALIASES.get(there, there)
            walk = seconds(row.get("환승소요시간(초)") or row.get("환승 소요시간(초)") or "")

            if station is None or here not in line_names or there not in line_names or walk <= 0:
                report.append(f"    ! 환승 데이터 매칭 실패: {raw_station} {here}↔{there}")
                continue
            for a, b in ((here, there), (there, here)):
                if (station, a, b) in seen:
                    continue
                seen.add((station, a, b))
                result.append({"station": station, "from": a, "to": b, "walkSeconds": float(walk)})
    return result


def segment_seconds(line_id, names, timing, circular):
    """계통의 구간별 주행 시간. 실측이 없는 구간은 기본값을 쓴다."""
    line_number = line_id.split("-")[0].removeprefix("L")
    pairs = list(zip(names, names[1:]))
    if circular:
        pairs.append((names[-1], names[0]))
    seconds, measured = [], 0
    for a, b in pairs:
        value = timing.get((line_number, normalize(a), normalize(b)))
        seconds.append(value or RUN_SECONDS)
        measured += 1 if value else 0
    return seconds, measured


def resolve(spec, by_line):
    """지선 소속 지정을 정규화 역명 집합으로 바꾼다 (역 이름 목록 또는 표준데이터 노선명)."""
    names = set()
    for item in spec:
        names |= by_line[item] if item in by_line else {normalize(item)}
    return names


def pick_row(candidates, allowed):
    """같은 이름의 역 중 이 노선의 행을 고른다. 없으면 수도권 행, 그마저 없으면 첫 행."""
    for row in candidates:
        if row["노선명"] in allowed:
            return row
    for row in candidates:
        if not any(k in row["노선명"] or k in row["운영기관명"] for k in NON_METRO):
            return row
    return candidates[0] if candidates else None


def station_entry(display_name, master, allowed, line_id, index, report):
    """표준데이터에서 영문명·좌표를 붙인다. 환승은 나중에 노선 목록에서 계산한다."""
    display_name = unicodedata.normalize("NFC", display_name).strip().replace(".", "·")
    candidates = master.get(normalize(display_name), [])
    row = pick_row(candidates, allowed)
    if row is None and normalize(display_name) not in ENGLISH_FALLBACK:
        report.append(f"    ! 표준데이터에 없음: {display_name} ({line_id})")
    return {
        "id": row["역번호"] if row else f"{line_id}-{index:03d}",
        "name": display_name,
        "nameEn": (row or {}).get("영문역사명", "") or ENGLISH_FALLBACK.get(normalize(display_name), ""),
        "transfers": [],
        "lat": float(row["역위도"]) if row and row.get("역위도") else None,
        "lon": float(row["역경도"]) if row and row.get("역경도") else None,
    }


def fill_transfers(lines, base_name):
    """환승 노선은 표준데이터 대신 우리가 만든 노선 목록에서 계산한다.
    표기 흔들림과 다른 도시 노선이 섞이는 문제를 없애고, 지선끼리는 환승으로 세지 않는다."""
    where = defaultdict(set)
    for line in lines:
        for station in line["stations"]:
            where[normalize(station["name"])].add(base_name[line["id"]])
    for line in lines:
        for station in line["stations"]:
            station["transfers"] = sorted(
                where[normalize(station["name"])] - {base_name[line["id"]]})


def build_line(mlit_name, line_id, display, short, color, allowed, order, master, by_line, timing, report):
    names = order[mlit_name]
    position = {normalize(n): i for i, n in enumerate(names)}
    branches = BRANCHES.get(mlit_name, [])

    owned = {}          # 정규화 역명 → 지선 이름
    sequences = []      # (지선 이름, [역명])
    spur_only = set()   # 셔틀 전용 역은 다른 계통에서 뺀다

    for branch, mode, junction, spec in branches:
        members = resolve(spec, by_line) & set(position)
        if mode == "fork" and any(item in by_line for item in spec):
            # 표준데이터 노선명으로 지정한 경우에만 분기역 이후로 자른다.
            # (그 노선의 앞부분은 모든 열차가 지나는 본선이기 때문)
            cut = position.get(normalize(junction), -1)
            members = {n for n in members if position[n] > cut}
        else:
            spur_only |= members
        for n in members:
            owned[n] = branch

    trunk = [n for n in names if normalize(n) not in owned]

    for branch, mode, junction, spec in branches:
        members = {n for n, b in owned.items() if b == branch}
        own = [n for n in names if normalize(n) in members]
        if mode == "segment":
            picked = own
        elif mode == "spur":
            # 본선을 뒤집은 노선이라도 지선은 분기역에서 바깥으로 나가는 순서를 유지한다
            own_seq = list(reversed(own)) if mlit_name in REVERSED else own
            picked = [n for n in names if normalize(n) == normalize(junction)] + own_seq
        else:  # fork
            cut = position.get(normalize(junction), -1)
            head = [n for n in trunk if position[normalize(n)] <= cut and normalize(n) not in spur_only]
            picked = head + own
        sequences.append((branch, picked))

    if mlit_name not in NO_MAIN:
        main = [n for n in trunk if normalize(n) not in spur_only]
        sequences.insert(0, (MAIN_BRANCH.get(mlit_name, "본선"), main))

    built = []
    for branch, picked in sequences:
        if len(picked) < 2:
            report.append(f"    ! 역이 부족한 계통: {display} {branch} ({len(picked)}개)")
            continue
        full_id = f"{line_id}-{branch}"
        suffix = "" if branch == "본선" else f" {branch}"
        stations = [station_entry(n, master, allowed, full_id, i, report) for i, n in enumerate(picked)]
        circular = full_id in CIRCULAR
        seconds, measured = segment_seconds(full_id, picked, timing, circular)
        forward, backward = DIRECTION_OVERRIDE.get(
            full_id, (f"{picked[-1]} 방면", f"{picked[0]} 방면"))
        built.append({
            "id": full_id,
            "name": display + suffix,
            "baseName": display,
            "shortName": short,
            "colorHex": color,
            "isCircular": circular,
            "directionNames": {"forward": forward, "backward": backward},
            "defaultRunSeconds": RUN_SECONDS,
            "defaultDwellSeconds": DWELL_SECONDS,
            "segmentSeconds": seconds,
            "measuredSegments": measured,
            "stations": stations,
        })

    built.extend(build_express(mlit_name, built, report))
    return built


def expand_stops(spec, base_names, position):
    """'...'을 앞뒤 정차역 사이의 모든 역으로 채운다 (각역정차 구간)."""
    stops = []
    for i, item in enumerate(spec):
        if item != "...":
            stops.append(item)
            continue
        before, after = position[normalize(spec[i - 1])], position[normalize(spec[i + 1])]
        step = 1 if after > before else -1
        stops.extend(base_names[k] for k in range(before + step, after, step))
    return stops


def build_express(mlit_name, built, report):
    """급행 계통을 기준 계통에서 뽑아낸다. 건너뛰는 역의 주행 시간을 합치고 속도 계수를 곱한다."""
    if mlit_name not in EXPRESS or not built:
        return []
    by_branch = {line["id"].split("-", 1)[1]: line for line in built}
    speedup = EXPRESS_SPEEDUP.get(mlit_name, EXPRESS_SPEEDUP["기본"])
    result = []

    for branch, base_branch, spec in EXPRESS[mlit_name]:
        base = by_branch.get(base_branch) or built[0]
        base_names = [s["name"] for s in base["stations"]]
        position = {normalize(n): i for i, n in enumerate(base_names)}

        unknown = [n for n in spec if n != "..." and normalize(n) not in position]
        if unknown:
            report.append(f"    ! 급행 정차역을 기준 계통에서 찾지 못함: {unknown[:5]} ({base['name']} {branch})")
            continue

        stops = expand_stops(spec, base_names, position)
        indices = [position[normalize(n)] for n in stops]
        if indices != sorted(indices):  # 기준 계통과 반대 방향으로 적었으면 맞춰 뒤집는다
            indices.reverse()
            stops.reverse()

        seconds = [
            round(sum(base["segmentSeconds"][a:b]) * speedup) for a, b in zip(indices, indices[1:])
        ]
        result.append({
            **base,
            "id": f"{base['id'].split('-', 1)[0]}-{branch}",
            "name": f"{base['name'].split(' ')[0]} {branch}",
            "isCircular": False,
            "directionNames": {"forward": f"{stops[-1]} 방면", "backward": f"{stops[0]} 방면"},
            "segmentSeconds": seconds,
            "measuredSegments": 0,
            "stations": [base["stations"][i] for i in indices],
        })
    return result


def main():
    parser = argparse.ArgumentParser(description="공공데이터 → network.json")
    parser.add_argument("--order", type=Path, required=True, help="국토부 도시철도 전체노선 CSV (UTF-8)")
    parser.add_argument("--master", type=Path, required=True, help="전국 도시철도 역사정보 XLSX")
    parser.add_argument("--timing", type=Path, help="서울교통공사 역간 거리·소요시간 CSV (UTF-8, 선택)")
    parser.add_argument("--transfers", type=Path, help="서울교통공사 환승역거리·소요시간 CSV (UTF-8, 선택)")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--version", default="2026.09.1")
    args = parser.parse_args()

    order = load_order(args.order)
    master, by_line = load_master(args.master)
    timing = load_timing(args.timing)
    report, lines, base_name = [], [], {}

    for mlit_name, line_id, display, short, color in LINES:
        if mlit_name not in order:
            report.append(f"  ! 순서 데이터에 없는 노선: {mlit_name}")
            continue
        allowed = LINE_MASTER.get(mlit_name, set())
        for line in build_line(mlit_name, line_id, display, short, color, allowed,
                               order, master, by_line, timing, report):
            lines.append(line)
            base_name[line["id"]] = display
            names = [s["name"] for s in line["stations"]]
            flags = []
            missing_en = sum(1 for s in line["stations"] if not s["nameEn"])
            dupes = [n for n, c in Counter(names).items() if c > 1]
            if missing_en:
                flags.append(f"영문명 없음 {missing_en}")
            if dupes:
                flags.append(f"중복역 {dupes}")
            measured = line.get("measuredSegments", 0)
            total = len(line.get("segmentSeconds", []))
            timing_note = f" · 실측 {measured}/{total}구간" if measured else ""
            print(f"  [{line['name']}] {len(names)}개 · {names[0]} → {names[-1]}{timing_note}"
                  + (f"  ⚠ {', '.join(flags)}" if flags else ""))

    fill_transfers(lines, base_name)

    station_names = {
        normalize(station["name"]): station["name"]
        for line in lines for station in line["stations"]
    }
    transfers = load_transfers(args.transfers, station_names, set(base_name.values()), report)
    print(f"\n환승 도보시간: {len(transfers)}쌍")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(
            {"version": args.version, "lines": lines, "transfers": transfers},
            ensure_ascii=False, indent=1),
        encoding="utf-8")

    total = sum(len(l["stations"]) for l in lines)
    print(f"\n노선 {len(lines)}개 · 역 {total}개 → {args.out}")
    if report:
        print("\n확인 필요:")
        print("\n".join(report[:40]))
        if len(report) > 40:
            print(f"  … 외 {len(report) - 40}건")
    return 0


if __name__ == "__main__":
    sys.exit(main())
