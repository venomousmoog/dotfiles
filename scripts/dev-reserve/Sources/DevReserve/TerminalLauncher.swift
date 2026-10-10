import AppKit
import DevReserveCore
import Foundation

@MainActor
struct TerminalLauncher {
  func open(
    application: TerminalApplication,
    hostname: String
  ) async throws {
    guard isValidReleaseHostname(hostname) else {
      throw TerminalLauncherError.invalidHostname
    }
    guard let devExecutableURL = DevCLI.locateDevExecutable() else {
      throw TerminalLauncherError.devExecutableNotFound
    }
    guard
      let source = TerminalLaunchCommand.script(
        devExecutablePath: devExecutableURL.path,
        hostname: hostname
      )
    else {
      throw TerminalLauncherError.invalidHostname
    }
    guard
      let applicationURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: application.bundleIdentifier
      )
    else {
      throw TerminalLauncherError.notInstalled(application)
    }

    let commandURL: URL
    do {
      commandURL = try writeCommand(source)
    } catch {
      throw TerminalLauncherError.commandFileFailed(error.localizedDescription)
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true

    do {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        NSWorkspace.shared.open(
          [commandURL],
          withApplicationAt: applicationURL,
          configuration: configuration
        ) { _, error in
          if let error {
            continuation.resume(
              throwing: TerminalLauncherError.openFailed(
                application,
                error.localizedDescription
              )
            )
          } else {
            continuation.resume(returning: ())
          }
        }
      }
    } catch {
      try? FileManager.default.removeItem(at: commandURL)
      throw error
    }
  }

  private func writeCommand(_ source: String) throws -> URL {
    let fileManager = FileManager.default
    guard let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
    else {
      throw CocoaError(.fileNoSuchFile)
    }
    let directory =
      cacheDirectory
      .appendingPathComponent("com.ddriver.devreserve", isDirectory: true)
      .appendingPathComponent("TerminalCommands", isDirectory: true)
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    removeStaleCommands(in: directory, fileManager: fileManager)

    let commandURL = directory.appendingPathComponent(
      "dev-connect-\(UUID().uuidString).command"
    )
    try source.write(to: commandURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: commandURL.path)
    return commandURL
  }

  private func removeStaleCommands(in directory: URL, fileManager: FileManager) {
    let cutoff = Date().addingTimeInterval(-3_600)
    guard
      let files = try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return
    }
    for file in files
    where file.lastPathComponent.hasPrefix("dev-connect-")
      && file.pathExtension == "command"
    {
      let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate
      if modified.map({ $0 < cutoff }) ?? true {
        try? fileManager.removeItem(at: file)
      }
    }
  }
}

enum TerminalLauncherError: Error, LocalizedError {
  case invalidHostname
  case devExecutableNotFound
  case notInstalled(TerminalApplication)
  case commandFileFailed(String)
  case openFailed(TerminalApplication, String)

  var errorDescription: String? {
    switch self {
    case .invalidHostname:
      return "This host does not have a valid DevEnv hostname."
    case .devExecutableNotFound:
      return DevCLIError.executableNotFound.localizedDescription
    case .notInstalled(let application):
      return "\(application.label) is not installed. Choose another terminal and try again."
    case .commandFileFailed(let message):
      return "DevReserve could not prepare the DevEnv connection: \(message)"
    case .openFailed(let application, let message):
      let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
      if !detail.isEmpty {
        return "DevReserve could not open \(application.label): \(detail)"
      }
      return "DevReserve could not open \(application.label)."
    }
  }
}
