// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FIMountKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FIMountKit", targets: ["FIMountKit"]),
    ],
    dependencies: [
        .package(path: "Dependencies/libewf-spm"),
        .package(path: "Dependencies/libvmdk-spm"),
        .package(path: "Dependencies/libvhdi-spm"),
        .package(path: "Dependencies/libcaff4-spm"),
    ],
    targets: [
        .target(
            name: "FIMountKit",
            dependencies: [
                .product(name: "LibEWF",   package: "libewf-spm"),
                .product(name: "LibVMDK",  package: "libvmdk-spm"),
                .product(name: "LibVHDI",  package: "libvhdi-spm"),
                .product(name: "Libcaff4", package: "libcaff4-spm"),
            ],
            path: "Sources/ImageMounter"
        ),
        .testTarget(
            name: "FIMountKitTests",
            dependencies: ["FIMountKit"],
            path: "Tests/ImageMounterTests"
        ),
    ]
)
