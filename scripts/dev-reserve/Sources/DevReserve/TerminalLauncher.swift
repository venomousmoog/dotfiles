import AppKit
import DevReserveCore
import Foundation

@MainActor
struct TerminalLauncher {
  func open(
    application: TerminalApplication,
    hostname: String
  ) async throws {
    guard let sshURL = TerminalLaunchURL.url(hostname: hostname) else {
      throw TerminalLauncherError.invalidHostname
    }
    guard
      let applicationURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: application.bundleIdentifier
      )
    else {
      throw TerminalLauncherError.notInstalled(application)
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true

    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      NSWorkspace.shared.open(
        [sshURL],
        withApplicationAt: applicationURL,
        configuration: configuration
      ) { _, error in
        if let error {
          continuation.resume(
            throwing: TerminalLauncherError.openFailed(application, error.localizedDescription)
          )
        } else {
          continuation.resume(returning: ())
        }
      }
    }
  }
}

enum TerminalLauncherError: Error, LocalizedError {
  case invalidHostname
  case notInstalled(TerminalApplication)
  case openFailed(TerminalApplication, String)

  var errorDescription: String? {
    switch self {
    case .invalidHostname:
      return "This host does not have a valid SSH hostname."
    case .notInstalled(let application):
      return "\(application.label) is not installed. Choose another terminal and try again."
    case .openFailed(let application, let message):
      let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
      if !detail.isEmpty {
        return "DevReserve could not open \(application.label): \(detail)"
      }
      return "DevReserve could not open \(application.label)."
    }
  }
}
