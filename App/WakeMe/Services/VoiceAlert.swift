import AVFoundation

/// 듣고 있는 오디오 위에 얹어 말하는 음성 알림.
///
/// 기획서의 문제 정의는 "노이즈캔슬링을 끼거나 졸고 있으면 놓치기 쉽다"는 것이다.
/// 진동과 배너는 그 사람에게 닿지 않는다. 귀에 직접 말을 거는 경로가 필요하다.
///
/// `duckOthers`로 듣던 음악을 잠깐 줄이고 그 위에 말을 얹은 뒤,
/// 끝나면 세션을 놓아 주어(`notifyOthersOnDeactivation`) 음악이 원래 크기로 돌아오게 한다.
/// 오디오를 못 잡는 상황(통화 중 등)에서는 조용히 포기한다 — 진동과 배너는 그대로 간다.
final class VoiceAlert: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        do {
            // .voicePrompt는 내비게이션 안내와 같은 취급이라 이어폰으로 제대로 나간다
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        // 기본 속도는 안내문에 조금 빠르다. 잠결에 듣는다는 것을 생각하면 천천히가 낫다.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.preUtteranceDelay = 0.2
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        releaseSession()
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        releaseSession()
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        releaseSession()
    }

    private nonisolated func releaseSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
