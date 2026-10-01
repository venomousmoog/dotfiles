import AppKit
import DevReserveCore
import Foundation

struct ITermLauncher {
  private static let bundleIdentifier = "com.googlecode.iterm2"

  func openTab(hostname: String) throws {
    guard let command = sshCommand(hostname: hostname) else {
      throw ITermLauncherError.invalidHostname
    }
    guard
      NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: Self.bundleIdentifier
      ) != nil
    else {
      throw ITermLauncherError.notInstalled
    }

    let source = """
      tell application id "\(Self.bundleIdentifier)"
        activate
        if (count of windows) is 0 then
          create window with default profile
        else
          tell current window to create tab with default profile
        end if
        tell current session of current window to write text "\(command)"
      end tell
      """
    guard let script = NSAppleScript(source: source) else {
      throw ITermLauncherError.scriptCreationFailed
    }

    var error: NSDictionary?
    script.executeAndReturnError(&error)
    if let error {
      let message = error[NSAppleScript.errorMessage] as? String
      throw ITermLauncherError.automationFailed(message)
    }
  }
}

enum ITermLauncherError: Error, LocalizedError {
  case invalidHostname
  case notInstalled
  case scriptCreationFailed
  case automationFailed(String?)

  var errorDescription: String? {
    switch self {
    case .invalidHostname:
      return "This host does not have a valid SSH hostname."
    case .notInstalled:
      return "iTerm is not installed. Install iTerm2 and try again."
    case .scriptCreationFailed:
      return "DevReserve could not prepare the iTerm command."
    case .automationFailed(let message):
      let detail = message?.trimmingCharacters(in: .whitespacesAndNewlines)
      if let detail, !detail.isEmpty {
        return "DevReserve could not open iTerm: \(detail)"
      }
      return
        "DevReserve could not open iTerm. Allow DevReserve to control iTerm in System Settings, then try again."
    }
  }
}
