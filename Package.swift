// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LiveAndAiChat",
    platforms: [
        // iOS 14 baseline: NWPathMonitor (iOS 12+), URLSessionWebSocketTask
        // (iOS 13+), Combine ObservableObject support is widest from 14
        // onwards, and gives us AsyncImage-friendly SwiftUI in Phase 2.B
        // without a backport library.
        .iOS(.v14),
        // macOS support is declared so `swift build` (which targets the
        // host on a Mac) compiles cleanly against the same APIs the iOS
        // target uses. Big Sur (11) has NWPathMonitor + URLSessionWebSocket
        // + OSLog at the minimum versions needed.
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "LiveAndAiChat",
            targets: ["LiveAndAiChat"]
        ),
    ],
    targets: [
        .target(
            name: "LiveAndAiChat",
            path: "Sources/LiveAndAiChat"
        ),
        .testTarget(
            name: "LiveAndAiChatTests",
            dependencies: ["LiveAndAiChat"],
            path: "Tests/LiveAndAiChatTests"
        ),
    ]
)
