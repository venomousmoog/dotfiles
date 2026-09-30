import Foundation

public struct DevListPayload: Decodable, Sendable {
  public let reserved: [DevListEntry]
  public let reservable: [DevListEntry]
}

public struct DevListEntry: Decodable, Sendable {
  public let created: String?
  public let expiresAt: String?
  public let hostname: String?
  public let isDisabled: Bool
  public let name: String
  public let status: String
  public let type: String

  public var isShortTermLease: Bool {
    type.hasPrefix("devserver:")
      && name.localizedCaseInsensitiveContains("(devserver v2)")
  }

  private enum CodingKeys: String, CodingKey {
    case created
    case expiresAt = "expires_at"
    case hostname
    case isDisabled = "is_disabled"
    case name
    case status
    case type
  }
}

public struct DevReservation: Identifiable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let hostname: String
  public let releaseHostname: String?
  public let type: String
  public let status: String
  public let created: String?
  public let expiresAt: Date?

  public init(entry: DevListEntry) {
    let explicitHostname = entry.hostname?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    hostname = explicitHostname.flatMap { $0.isEmpty ? nil : $0 } ?? entry.name
    id = hostname
    name = entry.name
    type = entry.type
    status = entry.status
    created = entry.created
    let parsedExpiration = entry.expiresAt.flatMap(ExpirationText.parse)
    expiresAt = parsedExpiration
    releaseHostname =
      parsedExpiration != nil
        && entry.status.trimmingCharacters(in: .whitespacesAndNewlines)
          .caseInsensitiveCompare("Active") == .orderedSame
      ? explicitHostname.flatMap { $0.isEmpty ? nil : $0 }
      : nil
  }
}

public struct ReservableOD: Identifiable, Equatable, Sendable {
  public let id: String
  public let rawType: String
  public let spec: String
  public let name: String
  public let status: String
  public let hardwareOption: String?

  public init?(
    rawType: String,
    name: String,
    status: String
  ) {
    guard rawType.hasPrefix("od:") else {
      return nil
    }

    let encodedSelection = String(rawType.dropFirst(3))
    let pieces = encodedSelection.split(
      separator: "?",
      maxSplits: 1,
      omittingEmptySubsequences: false
    )
    guard let first = pieces.first, !first.isEmpty, !first.hasPrefix("-") else {
      return nil
    }

    id = rawType
    self.rawType = rawType
    spec = String(first)
    self.name = name
    self.status = status
    hardwareOption =
      pieces.count == 2
      ? Self.queryValue(named: "hardware", in: String(pieces[1]))
      : nil
  }

  private static func queryValue(named key: String, in query: String) -> String? {
    for pair in query.split(separator: "&") {
      let parts = pair.split(
        separator: "=",
        maxSplits: 1,
        omittingEmptySubsequences: false
      )
      guard parts.count == 2, parts[0] == Substring(key) else {
        continue
      }
      let value = String(parts[1])
      return value.removingPercentEncoding ?? value
    }
    return nil
  }
}

public enum ReservationDuration: Int, CaseIterable, Identifiable, Sendable {
  case oneDay = 1
  case twoDays = 2
  case threeDays = 3
  case sixDays = 6

  public var id: Int { rawValue }

  public var label: String {
    "\(rawValue) \(rawValue == 1 ? "day" : "days")"
  }
}

public func prioritizeReservableODs(
  _ options: [ReservableOD],
  favorites: Set<String>,
  matching searchText: String
) -> [ReservableOD] {
  let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  let matchingOptions = options.filter { option in
    query.isEmpty
      || option.name.localizedCaseInsensitiveContains(query)
      || option.spec.localizedCaseInsensitiveContains(query)
  }

  return matchingOptions.sorted { left, right in
    let leftIsFavorite = favorites.contains(left.id)
    let rightIsFavorite = favorites.contains(right.id)
    if leftIsFavorite != rightIsFavorite {
      return leftIsFavorite
    }
    let nameOrder = left.name.localizedCaseInsensitiveCompare(right.name)
    if nameOrder != .orderedSame {
      return nameOrder == .orderedAscending
    }
    return left.id < right.id
  }
}

public struct DevInventory: Equatable, Sendable {
  public let reservations: [DevReservation]
  public let shortTermLeases: [DevReservation]
  public let devservers: [DevReservation]
  public let reservableODs: [ReservableOD]

  public init(payload: DevListPayload) {
    let reservationEntries = payload.reserved.filter { entry in
      !entry.type.hasPrefix("devserver:")
        || entry.expiresAt.flatMap(ExpirationText.parse) != nil
    }
    reservations =
      reservationEntries
      .map(DevReservation.init)
      .sorted { left, right in
        switch (left.expiresAt, right.expiresAt) {
        case (.some(let leftDate), .some(let rightDate)):
          return leftDate < rightDate
        case (.some, .none):
          return true
        case (.none, .some):
          return false
        case (.none, .none):
          return left.hostname.localizedCaseInsensitiveCompare(right.hostname) == .orderedAscending
        }
      }

    let reservationHostnames = Set(reservations.map(\.hostname))
    let allDevserverEntries = (payload.reserved + payload.reservable)
      .filter { entry in
        guard let hostname = entry.hostname else {
          return false
        }
        return entry.type.hasPrefix("devserver:")
          && !reservationHostnames.contains(hostname)
      }

    let shortTermLeaseEntries = allDevserverEntries.filter(\.isShortTermLease)
    shortTermLeases = Dictionary(
      grouping: shortTermLeaseEntries,
      by: { $0.hostname ?? $0.name }
    )
    .values
    .compactMap(\.first)
    .map(DevReservation.init)
    .sorted {
      $0.hostname.localizedCaseInsensitiveCompare($1.hostname) == .orderedAscending
    }

    let devserverEntries = allDevserverEntries.filter { !$0.isShortTermLease }
    devservers = Dictionary(grouping: devserverEntries, by: { $0.hostname ?? $0.name })
      .values
      .compactMap(\.first)
      .map(DevReservation.init)
      .sorted {
        $0.hostname.localizedCaseInsensitiveCompare($1.hostname) == .orderedAscending
      }

    reservableODs = payload.reservable
      .filter {
        !$0.isDisabled
          && $0.status.trimmingCharacters(in: .whitespacesAndNewlines) != "Available: 0"
      }
      .compactMap {
        ReservableOD(
          rawType: $0.type,
          name: $0.name,
          status: $0.status
        )
      }
      .sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
  }
}

public enum ExpirationText {
  public static func parse(_ value: String) -> Date? {
    if let date = try? Date(value, strategy: .iso8601) {
      return date
    }
    let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    return try? Date(value, strategy: fractional)
  }

  public static func relative(expiration: Date?, now: Date = Date()) -> String {
    guard let expiration else {
      return "No expiration reported"
    }

    let remaining = expiration.timeIntervalSince(now)
    guard remaining > 0 else {
      return "Expired"
    }

    if remaining >= 86_400 {
      let days = Int(remaining / 86_400)
      let hours = Int(remaining.truncatingRemainder(dividingBy: 86_400) / 3_600)
      return hours > 0 ? "\(days)d \(hours)h left" : "\(days)d left"
    }
    if remaining >= 3_600 {
      let hours = Int(ceil(remaining / 3_600))
      return "\(hours)h left"
    }
    let minutes = max(1, Int(ceil(remaining / 60)))
    return "\(minutes)m left"
  }

  public static func absolute(_ expiration: Date?) -> String {
    guard let expiration else {
      return "Expiration unavailable"
    }
    return expiration.formatted(date: .abbreviated, time: .shortened)
  }
}

public func isValidSessionName(_ name: String) -> Bool {
  guard name.count <= 64 else {
    return false
  }
  return name.allSatisfy { character in
    character.isASCII && (character.isLetter || character.isNumber || character == "_")
  }
}

public func isValidReleaseHostname(_ hostname: String) -> Bool {
  guard !hostname.isEmpty, hostname.count <= 253, !hostname.hasPrefix("-") else {
    return false
  }
  return hostname.allSatisfy { character in
    character.isASCII
      && (character.isLetter
        || character.isNumber
        || character == "."
        || character == "-"
        || character == "_")
  }
}
