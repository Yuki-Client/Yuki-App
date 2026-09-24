// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stoat",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "StoatCore",
            targets: ["StoatCore"]
        ),
        .library(
            name: "StoatState",
            targets: ["StoatState"]
        ),
        .library(
            name: "StoatVoice",
            targets: ["StoatVoice"]
        ),
        .library(
            name: "StoatUI",
            targets: ["StoatUI"]
        )
    ],
    dependencies: [
        // Stoat's voice calls run on LiveKit.
        .package(url: "https://github.com/livekit/client-sdk-swift", from: "2.17.0"),
        // Renders the LaTeX maths Stoat allows in messages and profiles.
        .package(url: "https://github.com/mgriebling/SwiftMath", from: "1.7.3"),
        // Stoat asks for an hCaptcha when creating an account or resetting a password.
        .package(url: "https://github.com/hCaptcha/HCaptcha-ios-sdk", from: "3.1.0"),
        // Cropping and straightening photos before sending them.
        .package(url: "https://github.com/benedom/SwiftyCrop", from: "2.1.0")
    ],
    targets: [
        .target(
            name: "StoatCore",
            dependencies: [],
            path: "Sources/StoatCore"
        ),
        .target(
            name: "StoatState",
            dependencies: ["StoatCore"],
            path: "Sources/StoatState"
        ),
        .target(
            name: "StoatVoice",
            dependencies: [
                "StoatCore",
                "StoatState",
                .product(name: "LiveKit", package: "client-sdk-swift")
            ],
            path: "Sources/StoatVoice"
        ),
        .target(
            name: "StoatUI",
            dependencies: [
                "StoatCore",
                "StoatState",
                "StoatVoice",
                .product(name: "SwiftMath", package: "SwiftMath"),
                .product(name: "HCaptcha", package: "HCaptcha-ios-sdk"),
                .product(name: "SwiftyCrop", package: "SwiftyCrop")
            ],
            path: "Sources/StoatUI"
        ),
        .testTarget(
            name: "StoatCoreTests",
            dependencies: ["StoatCore"],
            path: "Tests/StoatCoreTests"
        ),
        .testTarget(
            name: "StoatStateTests",
            dependencies: ["StoatCore", "StoatState"],
            path: "Tests/StoatStateTests"
        )
    ]
)
