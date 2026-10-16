// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PomodoroCore",
    products: [.library(name: "PomodoroCore", targets: ["PomodoroCore"])],
    targets: [
        .target(name: "PomodoroCore", path: "Pomodoro/Core"),
        .testTarget(name: "PomodoroCoreTests", dependencies: ["PomodoroCore"], path: "Tests/Core")
    ]
)
