// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CustosLibrarius-iOS",
    platforms: [.iOS(.v17)],
    products: [
        .executable(name: "CustosLibrarius-iOS", targets: ["CustosLibrarius-iOS"])
    ],
    targets: [
        .executableTarget(
            name: "CustosLibrarius-iOS",
            path: "."
        )
    ]
)
