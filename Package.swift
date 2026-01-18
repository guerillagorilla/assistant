// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VPA",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "vpa", targets: ["VPAApp"])
    ],
    targets: [
        .target(name: "VPAConfig"),
        .target(name: "VPACore", dependencies: ["VPAConfig"]),
        .target(name: "VPABot", dependencies: ["VPACore", "VPAConfig"]),
        .target(name: "VPAAudio", dependencies: ["VPACore"]),
        .target(name: "VPAInput", dependencies: ["VPACore"]),
        .target(name: "VPASTT", dependencies: ["VPACore", "VPAConfig"]),
        .target(name: "VPATTS", dependencies: ["VPACore", "VPAConfig"]),
        .target(name: "VPAResponse", dependencies: ["VPACore", "VPABot"]),
        .executableTarget(
            name: "VPAApp",
            dependencies: [
                "VPACore",
                "VPABot",
                "VPAAudio",
                "VPAInput",
                "VPASTT",
                "VPATTS",
                "VPAResponse",
                "VPAConfig"
            ]
        ),
        .testTarget(
            name: "VPACoreTests",
            dependencies: ["VPACore", "VPAResponse", "VPAConfig", "VPAAudio", "VPASTT", "VPABot"],
            resources: [.copy("AudioCorpus")]
        )
    ]
)
