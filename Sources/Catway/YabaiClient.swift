import Foundation

enum CatwayError: LocalizedError {
    case executableNotFound(String)
    case commandFailed(executable: String, arguments: [String], status: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case let .executableNotFound(name):
            return "Could not find \(name). Install it or set CATWAY_YABAI."
        case let .commandFailed(executable, arguments, status, message):
            let command = ([executable] + arguments).joined(separator: " ")
            return "Command failed (\(status)): \(command)\n\(message)"
        }
    }
}

struct ExecutableLocator {
    let environment: [String: String]
    let fileManager: FileManager

    init(environment: [String: String] = ProcessInfo.processInfo.environment, fileManager: FileManager = .default) {
        self.environment = environment
        self.fileManager = fileManager
    }

    func find(_ name: String, overrideVariable: String? = nil) -> String? {
        if let overrideVariable,
           let override = environment[overrideVariable],
           fileManager.isExecutableFile(atPath: override) {
            return override
        }

        let pathEntries = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let searchDirectories = pathEntries + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        for directory in searchDirectories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}

struct ProcessResult: Equatable, Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data
}

protocol ProcessRunning: Sendable {
    func run(executable: String, arguments: [String]) throws -> ProcessResult
}

struct SystemProcessRunner: ProcessRunning {
    func run(executable: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        return ProcessResult(
            status: process.terminationStatus,
            stdout: output.fileHandleForReading.readDataToEndOfFile(),
            stderr: errors.fileHandleForReading.readDataToEndOfFile()
        )
    }
}

struct YabaiClient: Sendable {
    let executable: String
    let runner: any ProcessRunning

    init(
        executable: String? = nil,
        locator: ExecutableLocator = ExecutableLocator(),
        runner: any ProcessRunning = SystemProcessRunner()
    ) throws {
        guard let executable = executable ?? locator.find("yabai", overrideVariable: "CATWAY_YABAI") else {
            throw CatwayError.executableNotFound("yabai")
        }
        self.executable = executable
        self.runner = runner
    }

    func loadWorkspaces(occupiedOnly: Bool = true) throws -> [WorkspaceModel] {
        let decoder = JSONDecoder()
        let spaces = try decoder.decode([RawSpace].self, from: run(["-m", "query", "--spaces"]))
        let windows = try decoder.decode([RawWindow].self, from: run(["-m", "query", "--windows"]))
        return WorkspaceCatalog.make(spaces: spaces, windows: windows, occupiedOnly: occupiedOnly)
    }

    func focus(index: Int) throws {
        _ = try run(["-m", "space", "--focus", String(index)])
    }

    @discardableResult
    func run(_ arguments: [String]) throws -> Data {
        let result = try runner.run(executable: executable, arguments: arguments)
        guard result.status == 0 else {
            let message = String(data: result.stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown yabai error"
            throw CatwayError.commandFailed(
                executable: executable,
                arguments: arguments,
                status: result.status,
                message: message
            )
        }
        return result.stdout
    }
}
