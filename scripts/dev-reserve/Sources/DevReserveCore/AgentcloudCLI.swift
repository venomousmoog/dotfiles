import Foundation

public struct AgentcloudSessionUsage: Identifiable, Equatable, Sendable {
  public let id: String
  public let title: String

  public init(id: String, title: String) {
    self.id = id
    self.title = title
  }
}

public struct AgentcloudUsageSnapshot: Equatable, Sendable {
  public let sessionsByHostname: [String: [AgentcloudSessionUsage]]

  public init(sessionsByHostname: [String: [AgentcloudSessionUsage]] = [:]) {
    self.sessionsByHostname = sessionsByHostname
  }

  public init(fleetData: Data, nodeData: Data) throws {
    let fleetRows = try JSONDecoder().decode([AgentcloudFleetRow].self, from: fleetData)
    let nodeRows = try JSONDecoder().decode([AgentcloudNodeRow].self, from: nodeData)

    var hostnameByNodeID: [String: String] = [:]
    for row in nodeRows {
      guard let host = row.instance?.host else {
        continue
      }
      hostnameByNodeID[Self.normalizeNodeID(row.nodeID)] = Self.normalizeNodeID(host)
    }

    var sessionsByIDByHostname: [String: [String: AgentcloudSessionUsage]] = [:]
    for row in fleetRows where row.running == true {
      let trimmedTitle = row.title?
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let displayTitle = trimmedTitle.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled session"
      let session = AgentcloudSessionUsage(
        id: row.sessionID,
        title: displayTitle
      )
      for nodeID in Set(row.attachedNodes ?? []) {
        let normalizedNodeID = Self.normalizeNodeID(nodeID)
        let hostname = hostnameByNodeID[normalizedNodeID] ?? normalizedNodeID
        sessionsByIDByHostname[hostname, default: [:]][session.id] = session
      }
    }

    sessionsByHostname = sessionsByIDByHostname.mapValues { sessionsByID in
      sessionsByID.values.sorted { left, right in
        let titleOrder = left.title.localizedCaseInsensitiveCompare(right.title)
        if titleOrder != .orderedSame {
          return titleOrder == .orderedAscending
        }
        return left.id < right.id
      }
    }
  }

  public func sessions(for hostname: String) -> [AgentcloudSessionUsage] {
    sessionsByHostname[Self.normalizeNodeID(hostname)] ?? []
  }

  public static func normalizeNodeID(_ value: String) -> String {
    var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    for suffix in [".facebook.com", ".fbinfra.net"] where normalized.hasSuffix(suffix) {
      normalized.removeLast(suffix.count)
      break
    }
    return normalized
  }
}

public enum AgentcloudCLIError: Error, LocalizedError, Sendable {
  case executableNotFound
  case commandFailed(String)
  case invalidResponse(String)

  public var errorDescription: String? {
    switch self {
    case .executableNotFound:
      return "Could not find `agentcloudctl` in /usr/local/bin, /opt/homebrew/bin, or PATH."
    case .commandFailed(let message):
      return "Could not load Agentcloud usage: \(message)"
    case .invalidResponse(let message):
      return "Could not read Agentcloud usage: \(message)"
    }
  }
}

public enum AgentcloudCommands {
  public static let runningFleet = [
    "fleet",
    "--sort",
    "recent",
    "--running",
    "--limit",
    "200",
  ]

  public static let nodeRoster = ["node", "list"]
}

public struct AgentcloudCLI: Sendable {
  public static let timeout: TimeInterval = 30

  private let runner: any CommandRunning

  public init(runner: any CommandRunning) {
    self.runner = runner
  }

  public init() throws {
    guard let executableURL = Self.locateExecutable() else {
      throw AgentcloudCLIError.executableNotFound
    }
    self.init(runner: ProcessRunner(executableURL: executableURL))
  }

  public func loadUsage() throws -> AgentcloudUsageSnapshot {
    let fleetOutput = try run(arguments: AgentcloudCommands.runningFleet)
    let nodeOutput = try run(arguments: AgentcloudCommands.nodeRoster)
    do {
      return try AgentcloudUsageSnapshot(
        fleetData: Data(fleetOutput.stdout.utf8),
        nodeData: Data(nodeOutput.stdout.utf8)
      )
    } catch {
      throw AgentcloudCLIError.invalidResponse(error.localizedDescription)
    }
  }

  public static func locateExecutable(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
  ) -> URL? {
    let fixedCandidates = [
      "/usr/local/bin/agentcloudctl",
      "/opt/homebrew/bin/agentcloudctl",
    ]
    for path in fixedCandidates where fileManager.isExecutableFile(atPath: path) {
      return URL(fileURLWithPath: path)
    }

    for directory in environment["PATH", default: ""].split(separator: ":") {
      let candidate = URL(fileURLWithPath: String(directory))
        .appendingPathComponent("agentcloudctl")
      if fileManager.isExecutableFile(atPath: candidate.path) {
        return candidate
      }
    }
    return nil
  }

  private func run(arguments: [String]) throws -> CommandOutput {
    do {
      return try runner.run(arguments: arguments, timeoutSeconds: Self.timeout)
    } catch {
      let message = error.localizedDescription
        .replacingOccurrences(of: "`dev`", with: "`agentcloudctl`")
      throw AgentcloudCLIError.commandFailed(message)
    }
  }
}

private struct AgentcloudFleetRow: Decodable {
  let sessionID: String
  let title: String?
  let running: Bool?
  let attachedNodes: [String]?

  private enum CodingKeys: String, CodingKey {
    case sessionID = "session_id"
    case title
    case running
    case attachedNodes = "attached_nodes"
  }
}

private struct AgentcloudNodeRow: Decodable {
  let nodeID: String
  let instance: AgentcloudNodeInstance?

  private enum CodingKeys: String, CodingKey {
    case nodeID = "node_id"
    case instance
  }
}

private struct AgentcloudNodeInstance: Decodable {
  let host: String?
}
