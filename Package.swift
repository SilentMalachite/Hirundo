// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Hirundo",
    platforms: [
        .macOS(.v13)
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
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.3.0"),
        // YAML パーサー
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        // テンプレートエンジン
        .package(url: "https://github.com/stencilproject/Stencil.git", from: "0.15.0"),
        // HTTPサーバー
        .package(url: "https://github.com/httpswift/swifter.git", .upToNextMajor(from: "1.5.0")),
        // Argument Parser
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0")
    ],
    targets: [
        // メインの実行可能ターゲット
        .executableTarget(
            name: "Hirundo",
            dependencies: [
                "HirundoCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
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
            ]
        ),
        // テストターゲット
        .testTarget(
            name: "HirundoTests",
            dependencies: ["HirundoCore"],
            exclude: ["Pending"]
        )
    ]
)