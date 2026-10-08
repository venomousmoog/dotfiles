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

public enum TerminalLaunchURL {
  public static func url(hostname: String) -> URL? {
    guard isValidReleaseHostname(hostname) else {
      return nil
    }

    var components = URLComponents()
    components.scheme = "ssh"
    components.host = hostname
    return components.url
  }
}
