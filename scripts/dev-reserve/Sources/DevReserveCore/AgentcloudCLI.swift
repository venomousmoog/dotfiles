import Foundation

public struct AgentcloudSessionUsage: Identifiable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let running: Bool
  public let lastActivityAt: Date?
  public let lastSequence: Int64

  public init(
    id: String,
    title: String,
    running: Bool,
    lastActivityAt: Date?,
    lastSequence: Int64
  ) {
    self.id = id
    self.title = title
    self.running = running
    self.lastActivityAt = lastActivityAt
    self.lastSequence = lastSequence
  }
}

public struct AgentcloudSessionGroups: Equatable, Sendable {
  public let working: [AgentcloudSessionUsage]
  public let attached: [AgentcloudSessionUsage]

  public init(_ sessions: [AgentcloudSessionUsage]) {
    working = sessions.filter(\.running)
    attached = sessions.filter { !$0.running }
  }
}

public struct AgentcloudNodeLease: Equatable, Sendable {
  public let holderSessionID: String
  public let expiresAt: Date
  public let heldByThisSession: Bool

  public init(
    holderSessionID: String,
    expiresAt: Date,
    heldByThisSession: Bool
  ) {
    self.holderSessionID = holderSessionID
    self.expiresAt = expiresAt
    self.heldByThisSession = heldByThisSession
  }
}

public enum AgentcloudNodeAttribution: Equatable, Sendable {
  case attached(primary: AgentcloudSessionUsage, others: [AgentcloudSessionUsage])
  case holder(session: AgentcloudSessionUsage?, lease: AgentcloudNodeLease)
  case unknown
}

public struct AgentcloudUsageSnapshot: Equatable, Sendable {
  public let sessionsByHostname: [String: [AgentcloudSessionUsage]]
  public let leasesByHostname: [String: AgentcloudNodeLease]
  public let advertisedHostnames: Set<String>

  private let sessionsByID: [String: AgentcloudSessionUsage]

  public init(
    sessionsByHostname: [String: [AgentcloudSessionUsage]] = [:],
    leasesByHostname: [String: AgentcloudNodeLease] = [:],
    advertisedHostnames: Set<String> = [],
    sessionsByID: [String: AgentcloudSessionUsage] = [:]
  ) {
    self.sessionsByHostname = sessionsByHostname
    self.leasesByHostname = leasesByHostname
    self.advertisedHostnames = advertisedHostnames
    self.sessionsByID = sessionsByID
  }

  public init(fleetData: Data, nodeData: Data) throws {
    let fleetRows = try JSONDecoder().decode([AgentcloudFleetRow].self, from: fleetData)
    let nodeRows = try JSONDecoder().decode([AgentcloudNodeRow].self, from: nodeData)

    var sessionIndex: [String: AgentcloudSessionUsage] = [:]
    for row in fleetRows {
      let trimmedTitle = row.title?
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let displayTitle = trimmedTitle.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled session"
      sessionIndex[row.sessionID] = AgentcloudSessionUsage(
        id: row.sessionID,
        title: displayTitle,
        running: row.running ?? false,
        lastActivityAt: row.lastEventUnixMS.flatMap { milliseconds in
          guard milliseconds > 0 else {
            return nil
          }
          return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
        },
        lastSequence: row.lastSequence ?? 0
      )
    }

    var hostnameByNodeID: [String: String] = [:]
    var leaseIndex: [String: AgentcloudNodeLease] = [:]
    var advertisedHosts: Set<String> = []
    for row in nodeRows {
      guard let host = row.instance?.host else {
        continue
      }
      let hostname = Self.normalizeNodeID(host)
      hostnameByNodeID[Self.normalizeNodeID(row.nodeID)] = hostname
      advertisedHosts.insert(hostname)
      if let lease = row.lease {
        let value = AgentcloudNodeLease(
          holderSessionID: lease.holderSession,
          expiresAt: Date(timeIntervalSince1970: TimeInterval(lease.expiresAtUnixMS) / 1_000),
          heldByThisSession: lease.heldByThisSession
        )
        if let existing = leaseIndex[hostname] {
          if value.expiresAt > existing.expiresAt {
            leaseIndex[hostname] = value
          }
        } else {
          leaseIndex[hostname] = value
        }
      }
    }

    var sessionsByIDByHostname: [String: [String: AgentcloudSessionUsage]] = [:]
    for row in fleetRows {
      guard let session = sessionIndex[row.sessionID] else {
        continue
      }
      for nodeID in Set(row.attachedNodes ?? []) {
        let normalizedNodeID = Self.normalizeNodeID(nodeID)
        let hostname = hostnameByNodeID[normalizedNodeID] ?? normalizedNodeID
        sessionsByIDByHostname[hostname, default: [:]][session.id] = session
      }
    }

    sessionsByHostname = sessionsByIDByHostname.mapValues { sessionsByID in
      sessionsByID.values.sorted(by: Self.sessionComesFirst)
    }
    leasesByHostname = leaseIndex
    advertisedHostnames = advertisedHosts
    sessionsByID = sessionIndex
  }

  public func sessions(for hostname: String) -> [AgentcloudSessionUsage] {
    sessionsByHostname[Self.normalizeNodeID(hostname)] ?? []
  }

  public func lease(for hostname: String) -> AgentcloudNodeLease? {
    leasesByHostname[Self.normalizeNodeID(hostname)]
  }

  public func isAdvertised(_ hostname: String) -> Bool {
    advertisedHostnames.contains(Self.normalizeNodeID(hostname))
  }

  public func attribution(for hostname: String) -> AgentcloudNodeAttribution {
    let sessions = sessions(for: hostname)
    if let primary = sessions.first {
      return .attached(primary: primary, others: Array(sessions.dropFirst()))
    }
    if let lease = lease(for: hostname) {
      return .holder(session: sessionsByID[lease.holderSessionID], lease: lease)
    }
    return .unknown
  }

  public static func normalizeNodeID(_ value: String) -> String {
    var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    for suffix in [".facebook.com", ".fbinfra.net"] where normalized.hasSuffix(suffix) {
      normalized.removeLast(suffix.count)
      break
    }
    return normalized
  }

  private static func sessionComesFirst(
    _ left: AgentcloudSessionUsage,
    _ right: AgentcloudSessionUsage
  ) -> Bool {
    if left.running != right.running {
      return left.running
    }
    switch (left.lastActivityAt, right.lastActivityAt) {
    case (.some(let leftDate), .some(let rightDate)) where leftDate != rightDate:
      return leftDate > rightDate
    case (.some, .none):
      return true
    case (.none, .some):
      return false
    default:
      break
    }
    if left.lastSequence != right.lastSequence {
      return left.lastSequence > right.lastSequence
    }
    return left.id < right.id
  }
}

public enum AgentcloudLeaseText {
  public static func label(expiresAt: Date, now: Date = Date()) -> String {
    guard expiresAt.timeIntervalSince1970 > 0 else {
      return "lease expiry unknown"
    }
    let delta = expiresAt.timeIntervalSince(now)
    if delta <= 0 {
      return "lease expired \(span(seconds: -delta)) ago"
    }
    return "lease \(span(seconds: delta)) left (expires \(utcMinute(expiresAt)))"
  }

  private static func span(seconds: TimeInterval) -> String {
    let minutes = Int(max(0, seconds) / 60)
    let days = minutes / 1_440
    let hours = (minutes % 1_440) / 60
    let remainingMinutes = minutes % 60
    if days > 0 {
      return "\(days)d\(hours)h"
    }
    if hours > 0 {
      return "\(hours)h\(remainingMinutes)m"
    }
    return "\(remainingMinutes)m"
  }

  private static func utcMinute(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    let components = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute],
      from: date
    )
    return String(
      format: "%04d-%02d-%02d %02d:%02dZ",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0,
      components.hour ?? 0,
      components.minute ?? 0
    )
  }
}

public enum AgentcloudSessionLink {
  public static func url(for sessionID: String) -> URL? {
    guard !sessionID.isEmpty else {
      return nil
    }
    var components = URLComponents(string: "https://agentcloud.internalmeta.com")
    components?.path = "/\(sessionID)"
    return components?.url
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
  public static let recentFleet = [
    "fleet",
    "--sort",
    "recent",
    "--limit",
    "500",
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
    let fleetOutput = try run(arguments: AgentcloudCommands.recentFleet)
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
  let lastEventUnixMS: Int64?
  let lastSequence: Int64?

  private enum CodingKeys: String, CodingKey {
    case sessionID = "session_id"
    case title
    case running
    case attachedNodes = "attached_nodes"
    case lastEventUnixMS = "last_event_unix_ms"
    case lastSequence = "last_seq"
  }
}

private struct AgentcloudNodeRow: Decodable {
  let nodeID: String
  let instance: AgentcloudNodeInstance?
  let lease: AgentcloudNodeLeaseRow?

  private enum CodingKeys: String, CodingKey {
    case nodeID = "node_id"
    case instance
    case lease
  }
}

private struct AgentcloudNodeInstance: Decodable {
  let host: String?
}

private struct AgentcloudNodeLeaseRow: Decodable {
  let holderSession: String
  let expiresAtUnixMS: Int64
  let heldByThisSession: Bool

  private enum CodingKeys: String, CodingKey {
    case holderSession = "holder_session"
    case expiresAtUnixMS = "expires_at_unix_ms"
    case heldByThisSession = "held_by_this_session"
  }
}
