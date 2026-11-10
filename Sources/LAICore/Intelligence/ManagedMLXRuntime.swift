import Foundation

enum ManagedMLXRuntime {
    private static let source=URL(string:"https://github.com/astral-sh/python-build-standalone/releases/download/20260127/cpython-3.12.12%2B20260127-aarch64-apple-darwin-install_only_stripped.tar.gz")!
    private static let archive=OptionalModelPackage.Asset("python.tar.gz",17_661_455,"ce209e54ac17f731b5f257ff419b55a445fcf65035e303bbbc5708d67dfe59d8")
    private static let readyFile=".mlx-lm-0.31.3"
    static var workerScript: URL? { Bundle.main.url(forResource:"mlx_summary",withExtension:"py") }

    static func python(in model: URL) -> URL {
        model.appendingPathComponent("runtime/python/bin/python3")
    }

    static func isReady(in model: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath:python(in:model).path) &&
            FileManager.default.fileExists(atPath:model.appendingPathComponent(readyFile).path)
    }

    static func prepare(in model:URL,download:@Sendable (URL) async throws -> URL) async throws {
        let manager=FileManager.default
        let file=try await download(source)
        defer { try? manager.removeItem(at:file) }
        guard try OptionalModelPackage.verify(file,asset:archive) else {
            throw LAIError.message("No se pudo verificar el entorno local de MLX.")
        }
        let runtime=model.appendingPathComponent("runtime",isDirectory:true)
        try manager.createDirectory(at:runtime,withIntermediateDirectories:true)
        try await run(URL(fileURLWithPath:"/usr/bin/tar"),["-xzf",file.path,"-C",runtime.path])
        let executable=python(in:model)
        try await run(executable,["-I","-m","pip","--isolated","install",
                                  "--index-url","https://pypi.org/simple","--only-binary=:all:",
                                  "--no-cache-dir","--disable-pip-version-check","--no-warn-script-location","--no-input",
                                  "mlx-lm==0.31.3","mlx==0.32.4","transformers==5.22.2"])
        try await run(executable,["-I","-c","import mlx.core; from mlx_lm import load, generate"])
        try Data().write(to:model.appendingPathComponent(readyFile))
    }

    private static func run(_ executable:URL,_ arguments:[String]) async throws {
        try Task.checkCancellation()
        let process=Process()
        process.executableURL=executable
        process.arguments=arguments
        process.environment=["PATH":"/usr/bin:/bin","PIP_CONFIG_FILE":"/dev/null","HF_HUB_OFFLINE":"1","TRANSFORMERS_OFFLINE":"1"]
        process.standardOutput=FileHandle.nullDevice
        process.standardError=FileHandle.standardError
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }
        while process.isRunning { try await Task.sleep(for:.milliseconds(150)) }
        try Task.checkCancellation()
        guard process.terminationStatus==0 else {
            throw LAIError.message("No se pudo preparar el entorno de MLX. Comprueba la conexión y vuelve a intentarlo.")
        }
    }
}
