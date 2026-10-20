// swift-tools-version: 6.2
import PackageDescription
import Foundation
let source=ProcessInfo.processInfo.environment["LAI_FLUID_SOURCE"] ?? "Vendor/FluidAudio"
let package=Package(name:"LAIFluidWorker",platforms:[.macOS("26.0")],dependencies:[.package(path:source)],targets:[
    .executableTarget(name:"FluidWorker",dependencies:[.product(name:"FluidAudio",package:"FluidAudio")])
],swiftLanguageModes:[.v6])
