import Foundation

/// 빌드할 때 주입되는 공개데이터 인증키.
///
/// 키는 소스에 두지 않는다. `App/Support/Secrets.xcconfig`(gitignore 대상)의 값이
/// Info.plist를 거쳐 들어오고, 그 파일이 없거나 비어 있으면 빈 문자열이 된다.
/// 빈 문자열이면 실시간 열차위치 보정만 꺼지고 나머지는 그대로 동작한다
/// (사용자가 설정 화면에서 직접 키를 넣으면 그 키를 쓴다).
///
/// 저장소를 받은 사람이 해야 할 일은 README "인증키" 절에 적어 두었다.
enum BuiltInKeys {
    /// 서울 열린데이터광장 (realtimePosition)
    static let realtimeSubway: String = {
        let value = Bundle.main.object(forInfoDictionaryKey: "RealtimeSubwayKey") as? String
        return (value ?? "").trimmingCharacters(in: .whitespaces)
    }()
}
