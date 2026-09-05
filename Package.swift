// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DualAudio",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DualAudio",
            path: "Sources/DualAudio",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
