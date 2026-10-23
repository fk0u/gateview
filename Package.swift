// swift-tools-version:5.7
// Compile check only (`swift build`). Ship via the Xcode app target.
import PackageDescription

let package = Package(
    name: "GateView",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "GateView",
            path: "GateView",
            exclude: ["Info.plist", "GateView.entitlements", "Assets.xcassets"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "GateView/Info.plist"])]
        )
    ]
)
