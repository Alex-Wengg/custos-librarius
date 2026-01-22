// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CustosLibrarius",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CustosLibrarius", targets: ["CustosLibrarius"]),
        .executable(name: "LLMTest", targets: ["LLMTest"]),
        .executable(name: "EmbeddingTest", targets: ["EmbeddingTest"]),
        .executable(name: "SearchTest", targets: ["SearchTest"]),
        .executable(name: "LLMQuickTest", targets: ["LLMQuickTest"]),
        .executable(name: "BackendTest", targets: ["BackendTest"]),
        .executable(name: "EndpointTest", targets: ["EndpointTest"]),
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
        // Embedding Test Runner
        .executableTarget(
            name: "EmbeddingTest",
            dependencies: [
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
            ],
            path: "EmbeddingTest"
        ),
        // Search Quality Test
        .executableTarget(
            name: "SearchTest",
            dependencies: [
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
            ],
            path: "SearchTest"
        ),
        // LLM Quick Test
        .executableTarget(
            name: "LLMQuickTest",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            path: "LLMQuickTest"
        ),
        // Full Backend Pipeline Test
        .executableTarget(
            name: "BackendTest",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
            ],
            path: "BackendTest"
        ),
        // Service Endpoint Tests
        .executableTarget(
            name: "EndpointTest",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
            ],
            path: "EndpointTest"
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
