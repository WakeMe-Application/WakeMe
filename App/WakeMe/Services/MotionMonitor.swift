import CoreMotion
import Foundation
import WakeMeEngine

/// 가속도계로 열차의 정차·출발을 감지한다.
/// 신호 처리는 엔진의 `StopDetector`가 하고, 여기서는 센서 값을 수평 가속도로 바꿔 넣어 준다.
/// 콜백은 센서 큐에서 불리므로 받는 쪽에서 메인 액터로 옮겨야 한다.
final class MotionMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "thisstop.motion", qos: .userInitiated)
    private let operationQueue = OperationQueue()
    private let motion = CMMotionManager()
    private let onEvent: @Sendable (MotionEvent) -> Void
    private var detector = StopDetector()

    init(onEvent: @escaping @Sendable (MotionEvent) -> Void) {
        self.onEvent = onEvent
        operationQueue.underlyingQueue = queue
        operationQueue.maxConcurrentOperationCount = 1
    }

    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    func start(hz: Double = 10) {
        guard motion.isDeviceMotionAvailable else { return }
        queue.async { self.detector.reset() }
        motion.deviceMotionUpdateInterval = 1 / hz
        motion.startDeviceMotionUpdates(to: operationQueue) { [weak self] data, _ in
            guard let self, let data else { return }
            self.handle(data)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }

    /// 수평 가속도 변환은 엔진(`MotionSample`)이 한다.
    /// 기록한 탑승 로그를 `ride-replay`로 재생할 때와 똑같은 식을 쓰기 위해서다.
    private func handle(_ data: CMDeviceMotion) {
        let a = data.userAcceleration
        let g = data.gravity
        let sample = MotionSample(
            time: Date(),
            userAcceleration: (a.x, a.y, a.z),
            gravity: (g.x, g.y, g.z))
        if let event = detector.consume(sample) {
            onEvent(event)
        }
    }
}
