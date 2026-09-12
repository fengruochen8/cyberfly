// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CyberFly",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CyberFlyCore", targets: ["CyberFlyCore"]),
        .library(name: "CyberFlySimulation", targets: ["CyberFlySimulation"]),
        .executable(name: "CyberFly", targets: ["CyberFlyApp"]),
        .executable(name: "CyberFlySelfTest", targets: ["CyberFlySelfTest"])
    ],
    targets: [
        .target(
            name: "CyberFlyCore",
            path: "Sources/CyberFlyCore"
        ),
        .target(
            name: "CyberFlySimulation",
            dependencies: ["CyberFlyCore"],
            path: "Sources/CyberFlySimulation"
        ),
        .executableTarget(
            name: "CyberFlyApp",
            dependencies: ["CyberFlyCore", "CyberFlySimulation"],
            path: "Sources/CyberFlyApp"
        ),
        .executableTarget(
            name: "CyberFlySelfTest",
            dependencies: ["CyberFlyCore", "CyberFlySimulation"],
            path: "Sources/CyberFlySelfTest"
        ),
        .testTarget(
            name: "CyberFlyCoreTests",
            dependencies: ["CyberFlyCore", "CyberFlySimulation"],
            path: "Tests/CyberFlyCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)

