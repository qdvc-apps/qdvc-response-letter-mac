// swift-tools-version: 5.10
//
// QDVC Response Letter for macOS — a native app for writing the response
// letter that goes with a revised journal manuscript: paste the decision
// letter, mark up the editors' and reviewers' comments, triage them, draft a
// response to each, and export the classic three-column Word table.
//
// Each response letter is a workspace folder of plain YAML and text files
// (see docs/FILE_FORMAT.md), designed to be tracked with Git.
//
// Build:   swift build            (or open this folder in Xcode)
// Test:    swift test
// Bundle:  scripts/build-app.sh   (ad-hoc signed .app, no Apple account needed)

import PackageDescription

var products: [Product] = [
    .library(name: "ResponseCore", targets: ["ResponseCore"]),
]
var targets: [Target] = [
    // Pure model layer: Foundation only (its own YAML reader and writer, its
    // own DOCX and ZIP writer), no AppKit/SwiftUI, unit-testable.
    .target(name: "ResponseCore"),
    .testTarget(
        name: "ResponseCoreTests",
        dependencies: ["ResponseCore"]
    ),
]

#if os(macOS)
// The SwiftUI/AppKit front-end. Declared on macOS only, so the core and its
// tests also build with a Linux Swift toolchain (docs/MAINTENANCE.md).
products.insert(.executable(name: "QDVCResponseLetter", targets: ["QDVCResponseLetter"]), at: 0)
targets.insert(.executableTarget(name: "QDVCResponseLetter", dependencies: ["ResponseCore"]), at: 1)
#endif

let package = Package(
    name: "QDVCResponseLetter",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
