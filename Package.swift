// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CustosLibrarius",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CustosLibrarius", targets: ["CustosLibrarius"]),
        .executable(name: "LLMTest", targets: ["LLMTest"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
    ],
    targets: [
        // Main executable with all sources
        .executableTarget(
            name: "CustosLibrarius",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
            ],
            path: "Sources",
            exclude: ["App/Info.plist", "TestRunner"]
        ),
        // LLM Test Runner (standalone with GPU access)
        .executableTarget(
            name: "LLMTest",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            path: "LLMTest"
        ),
        // Unit tests (non-LLM tests only)
        .testTarget(
            name: "CustosLibrariusTests",
            dependencies: ["CustosLibrarius"],
            path: "Tests"
        ),
        // LLM Integration tests (require GPU - run from Xcode)
        .testTarget(
            name: "LLMIntegrationTests",
            dependencies: ["CustosLibrarius"],
            path: "UITests"
        )
    ]
)
