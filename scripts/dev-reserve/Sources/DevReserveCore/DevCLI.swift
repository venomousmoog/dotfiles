import Darwin
import Foundation

public struct CommandOutput: Equatable, Sendable {
  public let stdout: String
  public let stderr: String
  public let exitCode: Int32

  public init(stdout: String, stderr: String, exitCode: Int32) {
    self.stdout = stdout
    self.stderr = stderr
    self.exitCode = exitCode
  }
}

public protocol CommandRunning: Sendable {
  func run(arguments: [String], timeoutSeconds: TimeInterval) throws -> CommandOutput
}

public enum DevCLIError: Error, LocalizedError, Sendable {
  case executableNotFound
  case launchFailed(String)
  case commandFailed(exitCode: Int32, message: String)
  case invalidResponse(String)
  case timedOut(TimeInterval)
  case cancelled

  public var errorDescription: String? {
    switch self {
    case .executableNotFound:
      return "Could not find the `dev` CLI in /usr/local/bin, /opt/homebrew/bin, or PATH."
    case .launchFailed(let message):
      return "Could not launch the `dev` CLI: \(message)"
    case .commandFailed(let exitCode, let message):
      return "`dev` exited with status \(exitCode): \(message)"
    case .invalidResponse(let message):
      return "Could not read the `dev` CLI response: \(message)"
    case .timedOut(let seconds):
      return
        "`dev` did not finish within \(Int(seconds)) seconds. Refresh inventory to check whether allocation succeeded."
    case .cancelled:
      return "Stopped waiting for `dev`. Refresh inventory to check whether allocation succeeded."
    }
  }
}

public struct ProcessRunner: CommandRunning, Sendable {
  private let executableURL: URL

  public init(executableURL: URL) {
    self.executableURL = executableURL
  }

  public func run(
    arguments: [String],
    timeoutSeconds: TimeInterval
  ) throws -> CommandOutput {
    let fileManager = FileManager.default
    let token = UUID().uuidString
    let stdoutURL = fileManager.temporaryDirectory
      .appendingPathComponent("dev-reserve-\(token).stdout")
    let stderrURL = fileManager.temporaryDirectory
      .appendingPathComponent("dev-reserve-\(token).stderr")

    fileManager.createFile(atPath: stdoutURL.path, contents: nil)
    fileManager.createFile(atPath: stderrURL.path, contents: nil)
    defer {
      try? fileManager.removeItem(at: stdoutURL)
      try? fileManager.removeItem(at: stderrURL)
    }

    let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
    let stderrHandle = try FileHandle(forWritingTo: stderrURL)
    defer {
      try? stdoutHandle.close()
      try? stderrHandle.close()
    }

    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = stdoutHandle
    process.standardError = stderrHandle
    process.environment = Self.environmentForGUIProcess()

    do {
      try process.run()
    } catch {
      throw DevCLIError.launchFailed(error.localizedDescription)
    }

    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while process.isRunning {
      if Task.isCancelled {
        stop(process)
        throw DevCLIError.cancelled
      }
      if Date() >= deadline {
        stop(process)
        throw DevCLIError.timedOut(timeoutSeconds)
      }
      Thread.sleep(forTimeInterval: 0.1)
    }
    process.waitUntilExit()

    try stdoutHandle.synchronize()
    try stderrHandle.synchronize()
    let stdoutData = try Data(contentsOf: stdoutURL)
    let stderrData = try Data(contentsOf: stderrURL)
    let output = CommandOutput(
      stdout: String(decoding: stdoutData, as: UTF8.self),
      stderr: String(decoding: stderrData, as: UTF8.self),
      exitCode: process.terminationStatus
    )

    guard output.exitCode == 0 else {
      let message =
        [output.stderr, output.stdout]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty } ?? "Unknown error"
      throw DevCLIError.commandFailed(
        exitCode: output.exitCode,
        message: message
      )
    }
    return output
  }

  private func stop(_ process: Process) {
    guard process.isRunning else {
      return
    }
    process.terminate()
    let gracefulDeadline = Date().addingTimeInterval(2)
    while process.isRunning, Date() < gracefulDeadline {
      Thread.sleep(forTimeInterval: 0.05)
    }
    if process.isRunning {
      kill(process.processIdentifier, SIGKILL)
    }
    process.waitUntilExit()
  }

  private static func environmentForGUIProcess() -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    let requiredPaths = [
      "/usr/local/bin",
      "/opt/homebrew/bin",
      "/usr/bin",
      "/bin",
      "/usr/sbin",
      "/sbin",
    ]
    let existing = environment["PATH", default: ""]
      .split(separator: ":")
      .map(String.init)
    environment["PATH"] = (existing + requiredPaths)
      .reduce(into: [String]()) { paths, candidate in
        if !paths.contains(candidate) {
          paths.append(candidate)
        }
      }
      .joined(separator: ":")
    return environment
  }
}

public enum DevCommands {
  public static let inventory = [
    "-q",
    "list",
    "--with-reservable",
    "--json",
  ]

  public static func reserve(
    option: ReservableOD,
    sessionName: String
  ) -> [String] {
    var arguments = [
      "-q",
      "connect",
      "-t",
      option.spec,
      "--expiration",
      "6",
      "--no-connect",
      "--no-connection-prompt",
      "--no-release-prompt",
      "--skip-host-setup",
      "--skip-homedir",
      "--restore-state-in-background",
      "--yubi",
      "push",
      "--entry-point",
      "dev_cli:dev_reserve_bar",
    ]
    if let hardwareOption = option.hardwareOption {
      arguments += ["--hardware-option", hardwareOption]
    }
    if !sessionName.isEmpty {
      arguments += ["--name", sessionName]
    }
    return arguments
  }
}

public struct DevCLI: Sendable {
  public static let inventoryTimeout: TimeInterval = 30
  public static let reservationTimeout: TimeInterval = 15 * 60

  private let runner: any CommandRunning

  public init(runner: any CommandRunning) {
    self.runner = runner
  }

  public init() throws {
    guard let executableURL = Self.locateDevExecutable() else {
      throw DevCLIError.executableNotFound
    }
    self.init(runner: ProcessRunner(executableURL: executableURL))
  }

  public func loadInventory() throws -> DevInventory {
    let output = try runner.run(
      arguments: DevCommands.inventory,
      timeoutSeconds: Self.inventoryTimeout
    )
    guard let data = output.stdout.data(using: .utf8) else {
      throw DevCLIError.invalidResponse("output was not UTF-8")
    }
    do {
      let payload = try JSONDecoder().decode(DevListPayload.self, from: data)
      return DevInventory(payload: payload)
    } catch {
      throw DevCLIError.invalidResponse(error.localizedDescription)
    }
  }

  @discardableResult
  public func reserve(
    option: ReservableOD,
    sessionName: String
  ) throws -> String {
    let output = try runner.run(
      arguments: DevCommands.reserve(
        option: option,
        sessionName: sessionName
      ),
      timeoutSeconds: Self.reservationTimeout
    )
    let message = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return message.isEmpty ? "Reservation completed." : message
  }

  public static func locateDevExecutable(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
  ) -> URL? {
    let fixedCandidates = [
      "/usr/local/bin/dev",
      "/opt/homebrew/bin/dev",
    ]
    for path in fixedCandidates where fileManager.isExecutableFile(atPath: path) {
      return URL(fileURLWithPath: path)
    }

    for directory in environment["PATH", default: ""].split(separator: ":") {
      let candidate = URL(fileURLWithPath: String(directory))
        .appendingPathComponent("dev")
      if fileManager.isExecutableFile(atPath: candidate.path) {
        return candidate
      }
    }
    return nil
  }
}
