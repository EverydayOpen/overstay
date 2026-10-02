// swift-tools-version:6.0
import PackageDescription

// OverstayCore is Foundation-only (builds and tests on Linux and Windows-Docker too).
// OverstayMac holds libproc/sysctl/Darwin, so it only exists on macOS. OverstayFixture is the tiny
// sleeping executable the Mac tests spawn as a stand-in for an orphaned tool server.
var products: [Product] = [.library(name: "OverstayCore", targets: ["OverstayCore"])]
var targets: [Target] = [
    .target(name: "OverstayCore"),
    // Fixtures are read from disk via #filePath, not bundled (keeps Linux builds warning-free).
    .testTarget(name: "OverstayCoreTests", dependencies: ["OverstayCore"], exclude: ["Fixtures"]),
]

#if os(macOS)
products.append(.library(name: "OverstayMac", targets: ["OverstayMac"]))
targets += [
    .target(name: "OverstayMac", dependencies: ["OverstayCore"]),
    .executableTarget(name: "OverstayFixture"),
    .testTarget(name: "OverstayMacTests", dependencies: ["OverstayMac", "OverstayCore"]),
]
#endif

let package = Package(
    name: "Overstay",
    // macOS 13: MenuBarExtra and ImageRenderer need it (BUILD_PLAN §1).
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets,
    // ponytail: Swift 5 mode keeps strict-concurrency diagnostics as warnings while the Mac code is unverified
    // on real hardware; move to .v6 once CI is green and warnings are cleaned up.
    swiftLanguageModes: [.v5]
)
