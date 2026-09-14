import Foundation

/// 서울 열린데이터광장 실시간 열차 위치정보 한 건.
/// https://data.seoul.go.kr — realtimePosition (HTTP만 제공해서 Info.plist에 ATS 예외를 둔다)
struct TrainPosition: Hashable, Sendable {
    enum Status: String, Sendable {
        /// 역 진입
        case approaching = "0"
        /// 역 도착
        case arrived = "1"
        /// 출발
        case departed = "2"
        /// 전역 출발
        case leftPreviousStation = "3"
    }

    let trainNumber: String
    let stationName: String
    let nextStationName: String
    let status: Status
    /// 상행·내선이면 true (API updnLine 0)
    let isUpLine: Bool
    let isExpress: Bool
    let receivedAt: Date
}

extension TrainPosition {
    /// 화면에 그대로 쓰는 현재 위치 문구.
    /// `leftPreviousStation`은 전역을 떠나 이 역으로 오는 중이라는 뜻이라 "접근 중"으로 적는다.
    var locationText: String {
        switch status {
        case .approaching: "\(stationName) 진입"
        case .arrived: "\(stationName) 도착"
        case .departed: "\(stationName) 출발"
        case .leftPreviousStation: "\(stationName) 접근 중"
        }
    }
}

enum TrainPositionError: Error {
    case missingKey
    case badResponse(Int)
    case service(String)
}

/// 노선 하나의 열차 위치를 가져온다. 키는 사용자가 설정에서 넣는다.
struct TrainPositionAPI: Sendable {
    let key: String
    var session: URLSession = .shared

    /// - Parameter line: API가 쓰는 노선 이름 ("2호선", "경의중앙선", "수인분당선" 등)
    func positions(line: String) async throws -> [TrainPosition] {
        guard !key.isEmpty else { throw TrainPositionError.missingKey }
        let encoded = line.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? line
        let url = URL(string: "http://swopenapi.seoul.go.kr/api/subway/\(key)/json/realtimePosition/0/200/\(encoded)")!

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw TrainPositionError.badResponse(http.statusCode)
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        if let error = payload.errorMessage, error.status != 200, let message = error.message {
            throw TrainPositionError.service(message)
        }
        return (payload.realtimePositionList ?? []).compactMap(TrainPosition.init)
    }

    /// 우리 노선 id를 API 노선명으로 바꾼다. 실시간 정보를 주지 않는 노선은 nil.
    /// (2026-09 확인: 인천 1·2호선, 김포골드라인, 에버라인, 의정부경전철은 제공되지 않는다)
    static func apiLineName(forLineID id: String) -> String? {
        let prefix = id.split(separator: "-").first.map(String.init) ?? id
        return supportedLines[prefix]
    }

    private static let supportedLines: [String: String] = [
        "L1": "1호선", "L2": "2호선", "L3": "3호선", "L4": "4호선", "L5": "5호선",
        "L6": "6호선", "L7": "7호선", "L8": "8호선", "L9": "9호선",
        "KG": "경의중앙선", "SB": "수인분당선", "SIN": "신분당선", "AREX": "공항철도",
        "GC": "경춘선", "GG": "경강선", "SH": "서해선", "UI": "우이신설선", "SILLIM": "신림선",
    ]

    // MARK: - 응답

    private struct Payload: Decodable {
        let errorMessage: ServiceMessage?
        let realtimePositionList: [Row]?
    }

    private struct ServiceMessage: Decodable {
        let status: Int?
        let message: String?
    }

    fileprivate struct Row: Decodable {
        let trainNo: String?
        let statnNm: String?
        let statnTnm: String?
        let trainSttus: String?
        let updnLine: String?
        let directAt: String?
        let recptnDt: String?
    }
}

extension TrainPosition {
    fileprivate init?(_ row: TrainPositionAPI.Row) {
        guard let trainNumber = row.trainNo, let stationName = row.statnNm else { return nil }
        self.trainNumber = trainNumber
        self.stationName = stationName
        nextStationName = row.statnTnm ?? ""
        status = Status(rawValue: row.trainSttus ?? "") ?? .approaching
        isUpLine = row.updnLine == "0"
        isExpress = (row.directAt ?? "0") != "0"
        receivedAt = TrainPosition.formatter.date(from: row.recptnDt ?? "") ?? Date()
    }

    /// "2026-09-14 11:27:00" (KST)
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        return formatter
    }()
}
