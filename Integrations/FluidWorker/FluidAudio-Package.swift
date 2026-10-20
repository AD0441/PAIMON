// swift-tools-version: 6.2
// Build manifest for unmodified FluidAudio 0.17.3 sources. NeMo text processing
// is unused by this ASR-only worker; exclude its 87 MB binary artifact entirely.
import PackageDescription
let package=Package(name:"FluidAudio",platforms:[.macOS("26.0")],products:[.library(name:"FluidAudio",targets:["FluidAudio"])],targets:[
    .target(name:"FluidAudio",dependencies:["FastClusterWrapper","MachTaskSelfWrapper"],path:"Sources/FluidAudio",exclude:["ASR/Parakeet/Unified/benchmark.md"],resources:[.process("TTS/LuxTts/G2p/Resources")]),
    .target(name:"FastClusterWrapper",path:"Sources/FastClusterWrapper",publicHeadersPath:"include"),
    .target(name:"MachTaskSelfWrapper",path:"Sources/MachTaskSelfWrapper",publicHeadersPath:"include")
],swiftLanguageModes:[.v6],cxxLanguageStandard:.cxx17)
