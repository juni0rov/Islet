// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Islet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Islet", targets: ["Islet"])
    ],
    targets: [
        .executableTarget(
            name: "Islet",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "IsletTests",
            dependencies: ["Islet"]
        )
    ]
)
