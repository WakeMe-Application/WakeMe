// swift-tools-version: 6.0
import PackageDescription

/// 깨워줘 판정 엔진 — Foundation만 의존한다 (기획서 13장 "엔진은 OS를 모르게").
let package = Package(
    name: "WakeMeEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WakeMeEngine", targets: ["WakeMeEngine"]),
        // 기록한 탑승 로그를 실제 StopDetector에 재생해 채점하는 도구 (맥에서 실행)
        .executable(name: "ride-replay", targets: ["RideReplay"]),
    ],
    targets: [
        .target(name: "WakeMeEngine", resources: [.process("Resources")]),
        .executableTarget(name: "RideReplay", dependencies: ["WakeMeEngine"]),
        .testTarget(name: "WakeMeEngineTests", dependencies: ["WakeMeEngine"]),
    ]
)
