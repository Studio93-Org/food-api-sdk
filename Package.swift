// swift-tools-version: 6.0
// The Swift SDK lives in swift/; this manifest sits at the repository root only because Swift Package Manager reads
// a package's manifest from the root of its repository.
import PackageDescription

let package = Package(
    name: "Studio93FoodAPI",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "Studio93FoodAPI", targets: ["Studio93FoodAPI"])
    ],
    targets: [
        .target(name: "Studio93FoodAPI", path: "swift/Sources/Studio93FoodAPI"),
        .testTarget(
            name: "Studio93FoodAPITests",
            dependencies: ["Studio93FoodAPI"],
            path: "swift/Tests/Studio93FoodAPITests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
