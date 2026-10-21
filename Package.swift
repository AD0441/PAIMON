// swift-tools-version: 6.2
import PackageDescription
import Foundation
// Local app bundles and version archives are optional build outputs.
let installedOutputs=["Local Audio Intelligence.app","PAIMON.app","Versiones"].filter {
    FileManager.default.fileExists(atPath:URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent($0).path)
}
let packagedArchives=(try? FileManager.default.contentsOfDirectory(atPath:URL(fileURLWithPath:#filePath).deletingLastPathComponent().path))?.filter{$0.hasPrefix("PAIMON-") && $0.hasSuffix(".zip")} ?? []
let package = Package(
    name: "LocalAudioIntelligence", platforms: [.macOS("26.0")],
    products: [.library(name: "LAICore", targets: ["LAICore"]),
               .executable(name: "LocalAudioIntelligence", targets: ["LAIApp"]),
               .executable(name: "LAICheck", targets: ["LAICheck"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "AudioRing", publicHeadersPath: "include", linkerSettings: [.linkedFramework("CoreAudio")]),
        .target(name: "LAICore", dependencies: ["AudioRing", "CSQLite"]),
        .executableTarget(name: "LAIApp", dependencies: ["LAICore"], path: ".", exclude: ["Sources", "Tests", "Tools", "docs", "Resources", "script", "Integrations", "README.md", "LocalAudioIntelligence.xcodeproj"]+installedOutputs+packagedArchives, sources: ["App", "Views", "ViewModels"]),
        .executableTarget(name: "LAICheck", dependencies: ["LAICore"], path: "Tools"),
        .testTarget(name: "LAICoreTests", dependencies: ["LAICore", "AudioRing"])
    ], swiftLanguageModes: [.v6])
