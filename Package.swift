// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PieMenu",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PieMenu", targets: ["PieMenu"]),
    ],
    targets: [
        // Menu-bar app: global hotkey → radial menu at the cursor. Apple frameworks only.
        .executableTarget(name: "PieMenu"),
    ],
    swiftLanguageVersions: [.v5]
)
