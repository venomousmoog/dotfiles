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

public enum TerminalLaunchCommand {
  public static func arguments(hostname: String) -> [String]? {
    guard isValidReleaseHostname(hostname) else {
      return nil
    }
    return [
      "connect",
      "--hostname",
      hostname,
      "--no-release-prompt",
      "--entry-point",
      "dev_cli:dev_reserve_bar",
    ]
  }

  public static func script(
    devExecutablePath: String,
    hostname: String
  ) -> String? {
    guard !devExecutablePath.isEmpty, let arguments = arguments(hostname: hostname) else {
      return nil
    }
    let command = ([devExecutablePath] + arguments)
      .map(posixQuoted)
      .joined(separator: " ")
    return """
      #!/bin/sh
      /bin/rm -f -- "$0"
      exec \(command)

      """
  }

  private static func posixQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
  }
}
