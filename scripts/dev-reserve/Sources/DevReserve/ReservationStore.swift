import AppKit
import Combine
import DevReserveCore
import Foundation

@MainActor
final class ReservationStore: ObservableObject {
  enum Surface: String, CaseIterable, Identifiable {
    case reservations = "Reservations"
    case reserve = "Reserve"

    var id: String { rawValue }
  }

  private static let lastSelectedOptionKey = "lastSelectedOptionID"
  private static let favoriteOptionIDsKey = "favoriteOptionIDs"
  private static let terminalApplicationKey = "terminalApplication"

  @Published var surface = Surface.reservations
  @Published var searchText = ""
  @Published var selectedOptionID: String?
  @Published var reservationDuration = ReservationDuration.sixDays
  @Published var sessionName = ""
  @Published var terminalApplication: TerminalApplication {
    didSet {
      UserDefaults.standard.set(
        terminalApplication.rawValue,
        forKey: Self.terminalApplicationKey
      )
    }
  }
  @Published var expandedAgentcloudHostIDs: Set<String> = []
  @Published private(set) var favoriteOptionIDs: Set<String> = []
  @Published private(set) var reservations: [DevReservation] = []
  @Published private(set) var shortTermLeases: [DevReservation] = []
  @Published private(set) var devservers: [DevReservation] = []
  @Published private(set) var reservableODs: [ReservableOD] = []
  @Published private(set) var agentcloudUsage = AgentcloudUsageSnapshot()
  @Published private(set) var isRefreshing = false
  @Published private(set) var isRefreshingAgentcloud = false
  @Published private(set) var isReserving = false
  @Published private(set) var releasingHostname: String?
  @Published private(set) var pendingRelease: DevReservation?
  @Published private(set) var lastUpdated: Date?
  @Published private(set) var statusMessage: String?
  @Published private(set) var operationError: String?
  @Published private(set) var refreshError: String?
  @Published private(set) var agentcloudUsageError: String?
  @Published private(set) var launchAtLoginMessage: String?

  private let cli: DevCLI?
  private let agentcloudCLI: AgentcloudCLI?
  private let terminalLauncher: TerminalLauncher
  private let notifier: ReservationNotifier
  private let startupError: String?
  private var refreshLoop: Task<Void, Never>?
  private var agentcloudRefreshLoop: Task<Void, Never>?
  private var agentcloudRefreshTask: Task<Void, Never>?
  private var reserveTask: Task<Void, Never>?
  private var releaseTask: Task<Void, Never>?
  private var hasStarted = false
  private var refreshRequested = false
  private var agentcloudRefreshRequested = false

  init(
    cli: DevCLI? = try? DevCLI(),
    agentcloudCLI: AgentcloudCLI? = try? AgentcloudCLI(),
    terminalLauncher: TerminalLauncher = TerminalLauncher(),
    notifier: ReservationNotifier = ReservationNotifier()
  ) {
    self.cli = cli
    self.agentcloudCLI = agentcloudCLI
    self.terminalLauncher = terminalLauncher
    self.notifier = notifier
    let savedTerminalApplication = UserDefaults.standard.string(
      forKey: Self.terminalApplicationKey
    )
    terminalApplication =
      savedTerminalApplication.flatMap(TerminalApplication.init(rawValue:)) ?? .iTerm
    favoriteOptionIDs = Set(
      UserDefaults.standard.stringArray(forKey: Self.favoriteOptionIDsKey) ?? []
    )
    startupError =
      cli == nil
      ? DevCLIError.executableNotFound.localizedDescription
      : nil
  }

  deinit {
    refreshLoop?.cancel()
    agentcloudRefreshLoop?.cancel()
    agentcloudRefreshTask?.cancel()
    reserveTask?.cancel()
    releaseTask?.cancel()
  }

  var filteredOptions: [ReservableOD] {
    prioritizeReservableODs(
      reservableODs,
      favorites: favoriteOptionIDs,
      matching: searchText
    )
  }

  var selectedOption: ReservableOD? {
    guard let selectedOptionID else {
      return nil
    }
    return reservableODs.first { $0.id == selectedOptionID }
  }

  var sessionNameIsValid: Bool {
    isValidSessionName(sessionName)
  }

  func agentcloudSessions(using hostname: String) -> [AgentcloudSessionUsage] {
    agentcloudUsage.sessions(for: hostname)
  }

  func agentcloudAttribution(for hostname: String) -> AgentcloudNodeAttribution {
    agentcloudUsage.attribution(for: hostname)
  }

  func isAgentcloudHostExpanded(_ hostname: String) -> Bool {
    expandedAgentcloudHostIDs.contains(AgentcloudUsageSnapshot.normalizeNodeID(hostname))
  }

  func toggleAgentcloudHost(_ hostname: String) {
    let id = AgentcloudUsageSnapshot.normalizeNodeID(hostname)
    if expandedAgentcloudHostIDs.contains(id) {
      expandedAgentcloudHostIDs.remove(id)
    } else {
      expandedAgentcloudHostIDs.insert(id)
    }
  }

  func openAgentcloudSession(_ sessionID: String) {
    guard let url = AgentcloudSessionLink.url(for: sessionID) else {
      return
    }
    NSWorkspace.shared.open(url)
  }

  func openTerminal(hostname: String) {
    let application = terminalApplication
    do {
      try terminalLauncher.open(
        application: application,
        hostname: hostname
      )
      operationError = nil
      let message = "Opened \(application.label) to \(hostname)"
      statusMessage = message
      Task { [weak self] in
        try? await Task.sleep(for: .seconds(2))
        if self?.statusMessage == message {
          self?.statusMessage = nil
        }
      }
    } catch {
      statusMessage = nil
      operationError = error.localizedDescription
    }
  }

  func start() {
    guard !hasStarted else {
      refresh()
      return
    }
    hasStarted = true
    refresh()
    refreshLoop = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(120))
        guard !Task.isCancelled else {
          return
        }
        await self?.refreshNow()
      }
    }
    agentcloudRefreshLoop = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(300))
        guard !Task.isCancelled else {
          return
        }
        await self?.refreshAgentcloudUsageNow()
      }
    }
  }

  func refresh() {
    refreshInventory()
    refreshAgentcloudUsage()
  }

  private func refreshInventory() {
    if isRefreshing {
      refreshRequested = true
      return
    }
    Task {
      await refreshNow()
    }
  }

  private func refreshAgentcloudUsage() {
    guard agentcloudCLI != nil else {
      agentcloudUsageError = AgentcloudCLIError.executableNotFound.localizedDescription
      return
    }
    if isRefreshingAgentcloud {
      agentcloudRefreshRequested = true
      return
    }
    agentcloudRefreshTask = Task { [weak self] in
      await self?.refreshAgentcloudUsageNow()
    }
  }

  private func refreshAgentcloudUsageNow() async {
    guard let agentcloudCLI else {
      agentcloudUsageError = AgentcloudCLIError.executableNotFound.localizedDescription
      return
    }
    guard !isRefreshingAgentcloud else {
      agentcloudRefreshRequested = true
      return
    }

    isRefreshingAgentcloud = true
    defer {
      isRefreshingAgentcloud = false
      agentcloudRefreshTask = nil
      if agentcloudRefreshRequested {
        agentcloudRefreshRequested = false
        refreshAgentcloudUsage()
      }
    }
    let worker = Task.detached(priority: .utility) {
      try agentcloudCLI.loadUsage()
    }
    do {
      let snapshot = try await withTaskCancellationHandler {
        try await worker.value
      } onCancel: {
        worker.cancel()
      }
      agentcloudUsage = snapshot
      agentcloudUsageError = nil
    } catch {
      agentcloudUsage = AgentcloudUsageSnapshot()
      agentcloudUsageError = error.localizedDescription
    }
  }

  func select(_ option: ReservableOD) {
    selectedOptionID = option.id
    UserDefaults.standard.set(
      option.id,
      forKey: Self.lastSelectedOptionKey
    )
  }

  func isFavorite(_ option: ReservableOD) -> Bool {
    favoriteOptionIDs.contains(option.id)
  }

  func toggleFavorite(_ option: ReservableOD) {
    if favoriteOptionIDs.contains(option.id) {
      favoriteOptionIDs.remove(option.id)
    } else {
      favoriteOptionIDs.insert(option.id)
    }
    UserDefaults.standard.set(
      favoriteOptionIDs.sorted(),
      forKey: Self.favoriteOptionIDsKey
    )
  }

  func reserveSelected() {
    guard let cli else {
      operationError = startupError
      return
    }
    guard let option = selectedOption else {
      operationError = "Choose an OD type first."
      return
    }
    guard sessionNameIsValid else {
      operationError =
        "Session name may contain only letters, numbers, and underscores, up to 64 characters."
      return
    }
    guard !isReserving else {
      return
    }
    guard releasingHostname == nil else {
      operationError = "Wait for the active release to finish."
      return
    }

    let requestedName = sessionName
    let requestedDuration = reservationDuration
    notifier.requestAuthorization()
    isReserving = true
    operationError = nil
    statusMessage =
      "Requesting a \(requestedDuration.label) \(option.spec) reservation. Approve the Duo push."

    reserveTask = Task { [weak self] in
      guard let self else {
        return
      }
      defer {
        isReserving = false
        reserveTask = nil
      }

      let worker = Task.detached(priority: .userInitiated) {
        try cli.reserve(
          option: option,
          sessionName: requestedName,
          duration: requestedDuration
        )
      }
      do {
        let message = try await withTaskCancellationHandler {
          try await worker.value
        } onCancel: {
          worker.cancel()
        }
        statusMessage = message
        notifier.reservationSucceeded(
          optionName: option.name,
          duration: requestedDuration
        )
        sessionName = ""
        surface = .reservations
        await refreshNow()
      } catch DevCLIError.cancelled {
        statusMessage = DevCLIError.cancelled.localizedDescription
        operationError = nil
        await refreshNow()
      } catch is CancellationError {
        statusMessage = DevCLIError.cancelled.localizedDescription
        operationError = nil
        await refreshNow()
      } catch {
        let errorMessage = error.localizedDescription
        statusMessage = nil
        operationError = errorMessage
        notifier.reservationFailed(
          optionName: option.name,
          duration: requestedDuration
        )
        await refreshNow()
      }
    }
  }

  func cancelReservation() {
    guard isReserving else {
      return
    }
    statusMessage = "Stopping the local `dev` command…"
    reserveTask?.cancel()
  }

  func requestRelease(_ reservation: DevReservation) {
    guard releasingHostname == nil, !isReserving else {
      return
    }
    guard
      let releaseHostname = reservation.releaseHostname,
      reservations.contains(where: {
        $0.id == reservation.id && $0.releaseHostname == releaseHostname
      })
    else {
      operationError = "This reservation is no longer eligible for release. Refresh and try again."
      return
    }
    pendingRelease = reservation
  }

  func cancelRelease() {
    pendingRelease = nil
  }

  func confirmRelease(_ reservation: DevReservation) {
    pendingRelease = nil
    guard
      let releaseHostname = reservation.releaseHostname,
      reservations.contains(where: {
        $0.id == reservation.id && $0.releaseHostname == releaseHostname
      })
    else {
      operationError = "This reservation is no longer active. Refresh and try again."
      return
    }
    release(hostname: releaseHostname)
  }

  private func release(hostname: String) {
    guard let cli else {
      operationError = startupError
      return
    }
    guard !isReserving else {
      operationError = "Wait for the active reservation request to finish."
      return
    }
    guard releasingHostname == nil else {
      return
    }

    releasingHostname = hostname
    operationError = nil
    statusMessage = "Releasing \(hostname)…"

    releaseTask = Task { [weak self] in
      guard let self else {
        return
      }
      defer {
        releasingHostname = nil
        releaseTask = nil
      }

      let worker = Task.detached(priority: .userInitiated) {
        try cli.release(hostname: hostname)
      }
      do {
        let message = try await withTaskCancellationHandler {
          try await worker.value
        } onCancel: {
          worker.cancel()
        }
        statusMessage = message
        reservations.removeAll { $0.releaseHostname == hostname }
        await refreshAfterMutation()
      } catch DevCLIError.cancelled {
        statusMessage = DevCLIError.cancelled.localizedDescription
        operationError = nil
        await refreshAfterMutation()
      } catch is CancellationError {
        statusMessage = DevCLIError.cancelled.localizedDescription
        operationError = nil
        await refreshAfterMutation()
      } catch {
        statusMessage = nil
        operationError = error.localizedDescription
        await refreshAfterMutation()
      }
    }
  }

  func copyHostname(_ hostname: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(hostname, forType: .string)
    let message = "Copied \(hostname)"
    statusMessage = message
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(2))
      if self?.statusMessage == message {
        self?.statusMessage = nil
      }
    }
  }

  func dismissOperationError() {
    operationError = nil
  }

  func dismissRefreshError() {
    refreshError = nil
  }

  func dismissAgentcloudUsageError() {
    agentcloudUsageError = nil
  }

  func setLaunchAtLoginMessage(_ message: String?) {
    launchAtLoginMessage = message
  }

  func dismissLaunchAtLoginMessage() {
    launchAtLoginMessage = nil
  }

  func quit() {
    NSApplication.shared.terminate(nil)
  }

  private func refreshAfterMutation() async {
    while isRefreshing, !Task.isCancelled {
      try? await Task.sleep(for: .milliseconds(50))
    }
    guard !Task.isCancelled else {
      return
    }
    await refreshNow()
  }

  private func refreshNow() async {
    guard let cli else {
      refreshError = startupError
      return
    }
    guard !isRefreshing else {
      refreshRequested = true
      return
    }

    isRefreshing = true
    defer {
      isRefreshing = false
      if refreshRequested {
        refreshRequested = false
        Task { [weak self] in
          await self?.refreshNow()
        }
      }
    }
    do {
      let inventory = try await Task.detached(priority: .utility) {
        try cli.loadInventory()
      }.value
      reservations = inventory.reservations
      shortTermLeases = inventory.shortTermLeases
      devservers = inventory.devservers
      reservableODs = inventory.reservableODs
      lastUpdated = Date()
      refreshError = nil
      restoreSelectionIfPossible()
    } catch {
      refreshError = error.localizedDescription
    }
  }

  private func restoreSelectionIfPossible() {
    if let selectedOptionID,
      reservableODs.contains(where: { $0.id == selectedOptionID })
    {
      return
    }
    let saved = UserDefaults.standard.string(
      forKey: Self.lastSelectedOptionKey
    )
    selectedOptionID = reservableODs.first(where: { $0.id == saved })?.id
  }
}
