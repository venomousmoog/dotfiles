import Foundation

public enum TerminalApplication: String, CaseIterable, Identifiable, Sendable {
  case iTerm = "iterm"
  case terminal = "terminal"

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .iTerm:
      return "iTerm"
    case .terminal:
      return "Terminal"
    }
  }

  public var bundleIdentifier: String {
    switch self {
    case .iTerm:
      return "com.googlecode.iterm2"
    case .terminal:
      return "com.apple.Terminal"
    }
  }
}

public enum TerminalLaunchScript {
  public static func source(
    application: TerminalApplication,
    hostname: String
  ) -> String? {
    guard let command = sshCommand(hostname: hostname) else {
      return nil
    }

    switch application {
    case .iTerm:
      return """
        tell application id "\(application.bundleIdentifier)"
          activate
          if (count of windows) is 0 then
            set targetWindow to (create window with default profile)
            set targetSession to current session of targetWindow
          else
            tell current window
              set targetTab to (create tab with default profile)
              set targetSession to current session of targetTab
            end tell
          end if

          set sessionReady to false
          repeat 100 times
            if not (is processing of targetSession) then
              set sessionReady to true
              exit repeat
            end if
            delay 0.1
          end repeat
          if not sessionReady then error "The new iTerm session did not become ready."
          delay 0.25
          tell targetSession to write text "\(command)"
        end tell
        """
    case .terminal:
      return """
        tell application id "\(application.bundleIdentifier)"
          do script "\(command)"
          activate
        end tell
        """
    }
  }
}
