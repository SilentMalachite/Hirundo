// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Hirundo",
    platforms: [
        .macOS(.v14)  // Updated for Swift 6 support
    ],
    products: [
        .executable(
            name: "hirundo",
            targets: ["Hirundo"]
        ),
        .library(
            name: "HirundoCore",
            targets: ["HirundoCore"]
        )
    ],
    dependencies: [
        // Markdown パーサー
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.6.0"),
        // YAML パーサー
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.2"),
        // テンプレートエンジン
        .package(url: "https://github.com/stencilproject/Stencil.git", from: "0.15.1"),
        // HTTPサーバー
        .package(url: "https://github.com/httpswift/swifter.git", .upToNextMajor(from: "1.5.0")),
        // Argument Parser
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.1")
    ],
    targets: [
        // メインの実行可能ターゲット
        .executableTarget(
            name: "Hirundo",
            dependencies: [
                "HirundoCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // コアライブラリターゲット
        .target(
            name: "HirundoCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Stencil", package: "Stencil"),
                .product(name: "Swifter", package: "swifter")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // テストターゲット
        .testTarget(
            name: "HirundoTests",
            dependencies: ["HirundoCore"],
            exclude: ["Pending"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)