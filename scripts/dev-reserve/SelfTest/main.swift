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
    "Live inventory: \(inventory.reservations.count) reservations, "
      + "\(inventory.devservers.count) devservers, "
      + "\(inventory.reservableODs.count) reservable OD types"
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

do {
  var tests = TestContext()
  try runModelTests(&tests)
  try runCommandTests(&tests)
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
