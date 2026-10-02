import AppKit
import DevReserveCore
import Foundation

struct TerminalLauncher {
  func open(
    application: TerminalApplication,
    hostname: String
  ) throws {
    guard
      let source = TerminalLaunchScript.source(
        application: application,
        hostname: hostname
      )
    else {
      throw TerminalLauncherError.invalidHostname
    }
    guard
      NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: application.bundleIdentifier
      ) != nil
    else {
      throw TerminalLauncherError.notInstalled(application)
    }
    guard let script = NSAppleScript(source: source) else {
      throw TerminalLauncherError.scriptCreationFailed(application)
    }

    var error: NSDictionary?
    script.executeAndReturnError(&error)
    if let error {
      let message = error[NSAppleScript.errorMessage] as? String
      throw TerminalLauncherError.automationFailed(application, message)
    }
  }
}

enum TerminalLauncherError: Error, LocalizedError {
  case invalidHostname
  case notInstalled(TerminalApplication)
  case scriptCreationFailed(TerminalApplication)
  case automationFailed(TerminalApplication, String?)

  var errorDescription: String? {
    switch self {
    case .invalidHostname:
      return "This host does not have a valid SSH hostname."
    case .notInstalled(let application):
      return "\(application.label) is not installed. Choose another terminal and try again."
    case .scriptCreationFailed(let application):
      return "DevReserve could not prepare the \(application.label) command."
    case .automationFailed(let application, let message):
      let detail = message?.trimmingCharacters(in: .whitespacesAndNewlines)
      if let detail, !detail.isEmpty {
        return "DevReserve could not open \(application.label): \(detail)"
      }
      return
        "DevReserve could not open \(application.label). Allow DevReserve to control it in System Settings, then try again."
    }
  }
}
