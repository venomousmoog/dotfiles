import DevReserveCore
import Foundation

private struct SelfTestFailure: Error, CustomStringConvertible {
  let description: String
}

private struct StubRunner: CommandRunning {
  let output: CommandOutput

  func run(
    arguments: [String],
    timeoutSeconds: TimeInterval
  ) throws -> CommandOutput {
    output
  }
}

private struct AgentcloudStubRunner: CommandRunning {
  let fleetJSON: String
  let nodeJSON: String?

  func run(
    arguments: [String],
    timeoutSeconds: TimeInterval
  ) throws -> CommandOutput {
    let stdout: String
    switch arguments {
    case AgentcloudCommands.recentFleet:
      stdout = fleetJSON
    case AgentcloudCommands.nodeRoster:
      guard let nodeJSON else {
        throw AgentcloudCLIError.commandFailed("node roster unavailable")
      }
      stdout = nodeJSON
    default:
      throw AgentcloudCLIError.commandFailed("unexpected arguments: \(arguments)")
    }
    return CommandOutput(stdout: stdout, stderr: "", exitCode: 0)
  }
}

private struct TestContext {
  private(set) var assertionCount = 0

  mutating func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
  ) throws {
    assertionCount += 1
    if !condition() {
      throw SelfTestFailure(description: message)
    }
  }
}

private let fixtureJSON = #"""
  {
    "reserved": [
      {
        "created": "Today at 08:54",
        "expires_at": "2026-10-06T23:54:58+00:00",
        "hostname": "devvm123.example.com",
        "is_disabled": false,
        "name": "[example] devvm123 (devserver v2)",
        "status": "Active",
        "type": "fbsource:default"
      },
      {
        "created": "2025-01-14 15:39",
        "hostname": "devhost.example.com",
        "is_disabled": false,
        "name": "Permanent devserver",
        "status": "Preferred: false",
        "type": "devserver:dev7_xlarge"
      }
    ],
    "reservable": [
      {
        "is_disabled": false,
        "name": "WWW (Hardware: Default)",
        "status": "Available: Unknown",
        "type": "od:www?hardware=Default"
      },
      {
        "is_disabled": true,
        "name": "Disabled OD",
        "status": "Available: 5",
        "type": "od:disabled"
      },
      {
        "is_disabled": false,
        "name": "Empty OD",
        "status": "Available: 0",
        "type": "od:empty"
      },
      {
        "hostname": "devhost.example.com",
        "is_disabled": false,
        "name": "Permanent devserver",
        "status": "Preferred: false",
        "type": "devserver:dev7_xlarge"
      },
      {
        "created": "2026-09-23 15:52",
        "hostname": "devvm12641.eag0.facebook.com",
        "is_disabled": false,
        "name": "devvm12641.eag0 (devserver v2)",
        "status": "Preferred: false; VPNLess: true",
        "type": "devserver:dev6_xlarge"
      }
    ]
  }
  """#

private func runModelTests(_ tests: inout TestContext) throws {
  let cli = DevCLI(
    runner: StubRunner(
      output: CommandOutput(
        stdout: fixtureJSON,
        stderr: "",
        exitCode: 0
      )
    )
  )
  let inventory = try cli.loadInventory()

  try tests.expect(inventory.reservations.count == 1, "expected one active OD reservation")
  try tests.expect(
    inventory.reservations[0].hostname == "devvm123.example.com",
    "expected the reservation hostname"
  )
  try tests.expect(
    inventory.reservations[0].expiresAt != nil,
    "expected the live expires_at format to parse"
  )
  try tests.expect(
    inventory.reservations[0].releaseHostname == "devvm123.example.com",
    "expected an active OD with an explicit hostname to be releasable"
  )
  try tests.expect(inventory.devservers.count == 1, "expected duplicate devservers to collapse")
  try tests.expect(
    inventory.devservers[0].releaseHostname == nil,
    "expected devservers to remain ineligible for release"
  )
  try tests.expect(
    inventory.shortTermLeases.count == 1,
    "expected Devserver V2 hosts to be classified as short-term leases"
  )
  try tests.expect(
    inventory.shortTermLeases[0].hostname == "devvm12641.eag0.facebook.com",
    "expected the short-term lease hostname"
  )
  try tests.expect(
    inventory.shortTermLeases[0].releaseHostname == nil,
    "expected an inactive Devserver V2 lease to remain ineligible for OD release"
  )
  try tests.expect(
    inventory.reservableODs.count == 1, "expected disabled and zero-capacity ODs to be hidden")
  try tests.expect(inventory.reservableODs[0].spec == "www", "expected the parsed OD spec")
  try tests.expect(
    inventory.reservableODs[0].hardwareOption == "Default",
    "expected the parsed hardware option"
  )

  let ineligibleReleaseJSON = #"""
    {
      "reserved": [
        {
          "is_disabled": false,
          "name": "Fallback display name",
          "status": "Active",
          "type": "fbsource:default"
        },
        {
          "hostname": "pending.od.fbinfra.net",
          "is_disabled": false,
          "name": "Pending OD",
          "status": "Pending",
          "type": "fbsource:default"
        }
      ],
      "reservable": []
    }
    """#
  let ineligiblePayload = try JSONDecoder().decode(
    DevListPayload.self,
    from: Data(ineligibleReleaseJSON.utf8)
  )
  let ineligibleInventory = DevInventory(payload: ineligiblePayload)
  try tests.expect(
    ineligibleInventory.reservations[0].releaseHostname == nil,
    "expected a display-name fallback to remain ineligible for release"
  )
  try tests.expect(
    ineligibleInventory.reservations[1].releaseHostname == nil,
    "expected a non-active OD to remain ineligible for release"
  )

  let malformed = DevCLI(
    runner: StubRunner(
      output: CommandOutput(stdout: "not-json", stderr: "", exitCode: 0)
    )
  )
  var rejectedMalformedJSON = false
  do {
    _ = try malformed.loadInventory()
  } catch DevCLIError.invalidResponse {
    rejectedMalformedJSON = true
  }
  try tests.expect(rejectedMalformedJSON, "expected malformed inventory to be rejected")
}

private func runCommandTests(_ tests: inout TestContext) throws {
  guard
    let option = ReservableOD(
      rawType: "od:www:lama?hardware=Default",
      name: "WWW - LaMa",
      status: "Available: Unknown"
    )
  else {
    throw SelfTestFailure(description: "expected a valid reservable OD")
  }
  try tests.expect(option.spec == "www:lama", "expected type and flavor to remain joined")
  try tests.expect(
    ReservableOD(rawType: "od:--help", name: "Bad", status: "") == nil,
    "expected leading-dash specs to be rejected"
  )
  guard
    let alphabeticOption = ReservableOD(
      rawType: "od:alpha",
      name: "Alpha",
      status: "Available: 1"
    )
  else {
    throw SelfTestFailure(description: "expected a second valid reservable OD")
  }
  let prioritized = prioritizeReservableODs(
    [alphabeticOption, option],
    favorites: [option.id],
    matching: ""
  )
  try tests.expect(
    prioritized.map(\.id) == [option.id, alphabeticOption.id],
    "expected favorites before alphabetical options"
  )
  try tests.expect(
    prioritizeReservableODs(
      [option, alphabeticOption],
      favorites: [option.id],
      matching: "alpha"
    ).map(\.id) == [alphabeticOption.id],
    "expected search to filter favorites and regular options alike"
  )

  let command = DevCommands.reserve(
    option: option,
    sessionName: "long_term",
    duration: .sixDays
  )
  try tests.expect(
    command.windows(ofCount: 2).contains(["--expiration", "6"]),
    "expected the default six-day request"
  )
  try tests.expect(
    ReservationDuration.allCases.map(\.rawValue) == [1, 2, 3, 6],
    "expected only CLI-supported reservation durations"
  )
  let twoDayCommand = DevCommands.reserve(
    option: option,
    sessionName: "",
    duration: .twoDays
  )
  try tests.expect(
    twoDayCommand.windows(ofCount: 2).contains(["--expiration", "2"]),
    "expected the selected duration in the request"
  )
  for requiredFlag in [
    "--no-connect",
    "--no-connection-prompt",
    "--no-release-prompt",
    "--skip-host-setup",
    "--skip-homedir",
    "--restore-state-in-background",
  ] {
    try tests.expect(command.contains(requiredFlag), "missing required flag \(requiredFlag)")
  }
  try tests.expect(
    command.windows(ofCount: 2).contains(["--yubi", "push"]),
    "expected Duo Push authentication"
  )
  try tests.expect(
    command.windows(ofCount: 2).contains(["--hardware-option", "Default"]),
    "expected hardware selection to survive parsing"
  )
  try tests.expect(
    command.windows(ofCount: 2).contains(["--name", "long_term"]),
    "expected the optional session name"
  )
  try tests.expect(
    DevCommands.inventory == ["-q", "list", "--with-reservable", "--json"],
    "expected the read-only inventory command"
  )
  let releaseCommand = try DevCommands.release(hostname: "1234.od.fbinfra.net")
  try tests.expect(
    releaseCommand == ["-q", "release", "--hostname", "1234.od.fbinfra.net"],
    "expected a non-interactive single-host release command"
  )
  var rejectedUnsafeHostname = false
  do {
    _ = try DevCommands.release(hostname: "--all")
  } catch DevCLIError.invalidResponse {
    rejectedUnsafeHostname = true
  }
  try tests.expect(rejectedUnsafeHostname, "expected unsafe release hostnames to be rejected")

  let emptyOutputCLI = DevCLI(
    runner: StubRunner(
      output: CommandOutput(stdout: "", stderr: "", exitCode: 0)
    )
  )
  let emptyReservationMessage = try emptyOutputCLI.reserve(
    option: option,
    sessionName: "",
    duration: .sixDays
  )
  try tests.expect(
    emptyReservationMessage == "Reservation completed.",
    "expected the empty-output success fallback"
  )
  let emptyReleaseMessage = try emptyOutputCLI.release(hostname: "1234.od.fbinfra.net")
  try tests.expect(
    emptyReleaseMessage == "Released 1234.od.fbinfra.net.",
    "expected the empty-output release fallback"
  )
}

private func runAgentcloudTests(_ tests: inout TestContext) throws {
  let fleetJSON = #"""
    [
      {
        "session_id": "session-active",
        "title": "Active\nwork",
        "running": true,
        "last_event_unix_ms": 1000,
        "last_seq": 1,
        "attached_nodes": [
          "friendly-node-id",
          "devvm33020.atn0.facebook.com"
        ]
      },
      {
        "session_id": "session-idle",
        "title": "Idle work",
        "running": false,
        "last_event_unix_ms": 2000,
        "last_seq": 10,
        "attached_nodes": ["friendly-node-id"]
      },
      {
        "session_id": "session-idle-low-seq",
        "title": "Earlier sequence",
        "running": false,
        "last_event_unix_ms": 2000,
        "last_seq": 5,
        "attached_nodes": ["friendly-node-id"]
      },
      {
        "session_id": "session-zero-event",
        "title": "Unknown activity",
        "running": false,
        "last_event_unix_ms": 0,
        "last_seq": 999,
        "attached_nodes": ["friendly-node-id"]
      },
      {
        "session_id": "session-other",
        "title": "Other node",
        "running": true,
        "last_event_unix_ms": 3000,
        "last_seq": 2,
        "attached_nodes": ["devgpu069.vll3.facebook.com"]
      }
    ]
    """#
  let nodeJSON = #"""
    [
      {
        "node_id": "friendly-node-id",
        "instance": {"host": "devvm33020.atn0.facebook.com"},
        "lease": {
          "holder_session": "session-other",
          "expires_at_unix_ms": 1893456000000,
          "held_by_this_session": false
        }
      },
      {
        "node_id": "leased-node",
        "instance": {"host": "devgpu013.cco5.facebook.com"},
        "lease": {
          "holder_session": "session-idle",
          "expires_at_unix_ms": 1893456000000,
          "held_by_this_session": false
        }
      },
      {
        "node_id": "unresolved-lease-node",
        "instance": {"host": "devvm999.example.com"},
        "lease": {
          "holder_session": "missing-holder-session",
          "expires_at_unix_ms": 1893456000000,
          "held_by_this_session": false
        }
      }
    ]
    """#
  let cli = AgentcloudCLI(
    runner: AgentcloudStubRunner(fleetJSON: fleetJSON, nodeJSON: nodeJSON)
  )
  let snapshot = try cli.loadUsage()
  let matchedSessions = snapshot.sessions(for: "DEVVM33020.ATN0.FACEBOOK.COM")
  try tests.expect(
    matchedSessions.map(\.id)
      == [
        "session-active",
        "session-idle",
        "session-idle-low-seq",
        "session-zero-event",
      ],
    "expected canonical running/activity/sequence ordering with aliases deduplicated"
  )
  let sessionGroups = AgentcloudSessionGroups(matchedSessions)
  try tests.expect(
    sessionGroups.working.map(\.id) == ["session-active"],
    "expected every working session to stay in the always-visible group"
  )
  try tests.expect(
    sessionGroups.attached.map(\.id)
      == ["session-idle", "session-idle-low-seq", "session-zero-event"],
    "expected the attached expander count to include only non-working sessions"
  )
  try tests.expect(
    matchedSessions[0].title == "Active work",
    "expected session titles to be safe for one-line tooltips"
  )
  try tests.expect(
    matchedSessions[0].running && !matchedSessions[1].running
      && !matchedSessions[2].running && !matchedSessions[3].running,
    "expected running and idle attachment state to survive parsing"
  )
  try tests.expect(
    matchedSessions[3].lastActivityAt == nil,
    "expected a nonpositive activity timestamp to remain unknown"
  )
  try tests.expect(
    snapshot.sessions(for: "devgpu069.vll3").map(\.id) == ["session-other"],
    "expected direct hostname matching without a roster alias"
  )

  var attachedAttributionIsCorrect = false
  if case .attached(let primary, let others) = snapshot.attribution(for: "devvm33020.atn0") {
    attachedAttributionIsCorrect =
      primary.id == "session-active"
      && others.map(\.id)
        == ["session-idle", "session-idle-low-seq", "session-zero-event"]
  }
  try tests.expect(
    attachedAttributionIsCorrect,
    "expected direct attachment evidence to outrank the lease holder claim"
  )

  var holderAttributionIsCorrect = false
  if case .holder(let session, let lease) = snapshot.attribution(for: "devgpu013.cco5") {
    holderAttributionIsCorrect =
      session?.id == "session-idle" && lease.holderSessionID == "session-idle"
  }
  try tests.expect(
    holderAttributionIsCorrect,
    "expected a lease holder fallback when no attachment is visible"
  )
  var unresolvedHolderIsPreserved = false
  if case .holder(let session, let lease) = snapshot.attribution(for: "devvm999.example.com") {
    unresolvedHolderIsPreserved =
      session == nil && lease.holderSessionID == "missing-holder-session"
  }
  try tests.expect(
    unresolvedHolderIsPreserved,
    "expected an unresolved lease holder ID to remain available for linking"
  )
  try tests.expect(
    AgentcloudSessionLink.url(for: "missing-holder-session")?.absoluteString
      == "https://agentcloud.internalmeta.com/missing-holder-session",
    "expected a canonical Agentcloud session URL"
  )

  let leaseExpiry = try Date("2026-07-17T02:32:00Z", strategy: .iso8601)
  try tests.expect(
    AgentcloudLeaseText.label(
      expiresAt: leaseExpiry,
      now: leaseExpiry.addingTimeInterval(-((60 + 32) * 60))
    ) == "lease 1h32m left (expires 2026-07-17 02:32Z)",
    "expected remaining and absolute UTC lease timing"
  )
  try tests.expect(
    AgentcloudLeaseText.label(
      expiresAt: leaseExpiry,
      now: leaseExpiry.addingTimeInterval(12 * 60)
    ) == "lease expired 12m ago",
    "expected an explicit expired lease duration"
  )
  try tests.expect(
    AgentcloudLeaseText.label(expiresAt: Date(timeIntervalSince1970: 0))
      == "lease expiry unknown",
    "expected a nonpositive lease expiry to remain unknown"
  )

  try tests.expect(
    snapshot.attribution(for: "unused.example.com") == .unknown,
    "expected unknown rather than an unsupported claim that a host is free"
  )
  try tests.expect(
    snapshot.isAdvertised("devgpu013.cco5.facebook.com"),
    "expected roster presence to survive hostname normalization"
  )
  try tests.expect(
    AgentcloudCommands.recentFleet
      == ["fleet", "--sort", "recent", "--limit", "500"],
    "expected a bounded recent-session fleet request"
  )
  try tests.expect(
    AgentcloudCommands.nodeRoster == ["node", "list"],
    "expected node aliases and leases to come from the supported roster command"
  )
  var rejectedMissingRoster = false
  do {
    _ = try AgentcloudCLI(
      runner: AgentcloudStubRunner(fleetJSON: fleetJSON, nodeJSON: nil)
    ).loadUsage()
  } catch AgentcloudCLIError.commandFailed {
    rejectedMissingRoster = true
  }
  try tests.expect(
    rejectedMissingRoster,
    "expected a missing node roster to make Agentcloud usage unavailable"
  )
}

private func runProcessTests(_ tests: inout TestContext) throws {
  let shell = ProcessRunner(executableURL: URL(fileURLWithPath: "/bin/sh"))
  var preferredStderr = false
  do {
    _ = try shell.run(
      arguments: ["-c", "printf stdout; printf stderr >&2; exit 7"],
      timeoutSeconds: 2
    )
  } catch DevCLIError.commandFailed(let exitCode, let message) {
    preferredStderr = exitCode == 7 && message == "stderr"
  }
  try tests.expect(preferredStderr, "expected stderr to describe command failures")

  var enforcedTimeout = false
  do {
    _ = try shell.run(
      arguments: ["-c", "while :; do :; done"],
      timeoutSeconds: 0.1
    )
  } catch DevCLIError.timedOut {
    enforcedTimeout = true
  }
  try tests.expect(enforcedTimeout, "expected a hung command to time out")
}

private func runFormattingTests(_ tests: inout TestContext) throws {
  try tests.expect(isValidSessionName(""), "expected an empty session name to be allowed")
  try tests.expect(isValidSessionName("feature_123"), "expected a valid session name")
  try tests.expect(!isValidSessionName("feature-name"), "expected punctuation to be rejected")
  try tests.expect(
    !isValidSessionName(String(repeating: "a", count: 65)),
    "expected overlong session names to be rejected"
  )
  try tests.expect(
    isValidReleaseHostname("1234.od.fbinfra.net"),
    "expected a normal OD hostname to be releasable"
  )
  try tests.expect(
    !isValidReleaseHostname("--all"),
    "expected a leading-dash release hostname to be rejected"
  )
  try tests.expect(
    !isValidReleaseHostname("host name"),
    "expected whitespace in a release hostname to be rejected"
  )
  try tests.expect(
    TerminalApplication(rawValue: "iterm") == .iTerm
      && TerminalApplication(rawValue: "terminal") == .terminal,
    "expected persisted terminal choices to decode"
  )
  let terminalURL = try DevCLIError.invalidResponse("missing SSH launch URL").unwrap(
    TerminalLaunchURL.url(hostname: "devvm123.example.com")
  )
  try tests.expect(
    terminalURL.absoluteString == "ssh://devvm123.example.com"
      && terminalURL.scheme == "ssh"
      && terminalURL.host == "devvm123.example.com",
    "expected a validated shell-independent SSH URL"
  )
  try tests.expect(
    TerminalLaunchURL.url(hostname: "foo_bar.example.com")?.absoluteString
      == "ssh://foo_bar.example.com",
    "expected DevEnv hostnames containing underscores to remain supported"
  )
  try tests.expect(
    TerminalLaunchURL.url(hostname: "host; open -a Calculator") == nil
      && TerminalLaunchURL.url(hostname: "--all") == nil
      && TerminalLaunchURL.url(hostname: "host name") == nil,
    "expected unsafe hostnames to produce no terminal URL"
  )

  try tests.expect(
    WindowDimensions(width: 500, height: 760) == .defaultValue,
    "expected the default menu-window dimensions"
  )
  try tests.expect(
    WindowDimensions(width: 459, height: 760) == nil
      && WindowDimensions(width: 500, height: 619) == nil,
    "expected undersized menu-window dimensions to be rejected"
  )
  try tests.expect(
    WindowDimensions(width: .nan, height: 760) == nil
      && WindowDimensions(width: 500, height: .infinity) == nil,
    "expected non-finite menu-window dimensions to be rejected"
  )
  try tests.expect(
    WindowDimensions(width: 1_200, height: 1_000)?.clamped(
      maxWidth: 900,
      maxHeight: 700
    ) == WindowDimensions(width: 900, height: 700),
    "expected restored menu-window dimensions to clamp to visible bounds"
  )

  let now = Date(timeIntervalSince1970: 1_000)
  try tests.expect(
    ExpirationText.relative(
      expiration: now.addingTimeInterval((5 * 86_400) + 3_600),
      now: now
    ) == "5d 1h left",
    "expected a non-inflated day-and-hour countdown"
  )
  try tests.expect(
    ExpirationText.relative(
      expiration: now.addingTimeInterval(90 * 60),
      now: now
    ) == "2h left",
    "expected an hour-level countdown"
  )
  try tests.expect(
    ExpirationText.relative(
      expiration: now.addingTimeInterval(30),
      now: now
    ) == "1m left",
    "expected the sub-minute floor"
  )
  try tests.expect(
    ExpirationText.relative(
      expiration: now.addingTimeInterval(-1),
      now: now
    ) == "Expired",
    "expected an expired label"
  )
}

private func runLiveInventoryTest(_ tests: inout TestContext) throws {
  let executable = try DevCLIError.executableNotFound.unwrap(
    DevCLI.locateDevExecutable()
  )
  try tests.expect(
    executable.path == "/usr/local/bin/dev" || executable.path.hasSuffix("/dev"),
    "expected to locate the dev CLI"
  )

  let inventory = try DevCLI().loadInventory()
  try tests.expect(!inventory.reservableODs.isEmpty, "expected live DevEnv OD types")
  print(
    "Live inventory: \(inventory.reservations.count) active reservations, "
      + "\(inventory.shortTermLeases.count) short-term devserver leases, "
      + "\(inventory.devservers.count) long-lived devservers, "
      + "\(inventory.reservableODs.count) reservable OD types"
  )

  guard AgentcloudCLI.locateExecutable() != nil else {
    throw AgentcloudCLIError.executableNotFound
  }
  let usage = try AgentcloudCLI().loadUsage()
  let allSessions = usage.sessionsByHostname.values.flatMap { $0 }
  let sessionIDs = Set(allSessions.map(\.id))
  let runningSessionIDs = Set(allSessions.filter(\.running).map(\.id))
  print(
    "Agentcloud usage: \(runningSessionIDs.count) running / \(sessionIDs.count) attached "
      + "sessions across \(usage.sessionsByHostname.count) nodes"
  )
}

extension DevCLIError {
  fileprivate func unwrap<Value>(_ value: Value?) throws -> Value {
    guard let value else {
      throw self
    }
    return value
  }
}

extension Array {
  fileprivate func windows(ofCount count: Int) -> [[Element]] {
    guard count > 0, self.count >= count else {
      return []
    }
    return (0...(self.count - count)).map { index in
      Array(self[index..<(index + count)])
    }
  }
}

if CommandLine.arguments.contains("--print-terminal-url"),
  let url = TerminalLaunchURL.url(hostname: "devvm123.example.com")
{
  print(url.absoluteString)
  exit(0)
}

do {
  var tests = TestContext()
  try runModelTests(&tests)
  try runCommandTests(&tests)
  try runAgentcloudTests(&tests)
  try runProcessTests(&tests)
  try runFormattingTests(&tests)
  if CommandLine.arguments.contains("--live") {
    try runLiveInventoryTest(&tests)
  }
  print("DevReserve self-test passed (\(tests.assertionCount) assertions)")
} catch {
  fputs("DevReserve self-test failed: \(error)\n", stderr)
  exit(1)
}
