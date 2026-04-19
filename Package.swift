// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "XArticleReader",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "XArticleReader", targets: ["XArticleReader"]),
    ],
    targets: [
        .executableTarget(
            name: "XArticleReader",
            path: "Sources/XArticleReader"
        ),
    ]
)
