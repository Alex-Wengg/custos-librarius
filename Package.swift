// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CustosLibrarius",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CustosLibrarius", targets: ["CustosLibrarius"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "CustosLibrarius",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
            ],
            path: "Sources"
        )
    ]
)
