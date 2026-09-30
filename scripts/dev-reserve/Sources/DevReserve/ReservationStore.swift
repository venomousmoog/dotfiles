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

  @Published var surface = Surface.reservations
  @Published var searchText = ""
  @Published var selectedOptionID: String?
  @Published var sessionName = ""
  @Published private(set) var reservations: [DevReservation] = []
  @Published private(set) var devservers: [DevReservation] = []
  @Published private(set) var reservableODs: [ReservableOD] = []
  @Published private(set) var isRefreshing = false
  @Published private(set) var isReserving = false
  @Published private(set) var lastUpdated: Date?
  @Published private(set) var statusMessage: String?
  @Published private(set) var operationError: String?
  @Published private(set) var refreshError: String?
  @Published private(set) var launchAtLoginMessage: String?

  private let cli: DevCLI?
  private let startupError: String?
  private var refreshLoop: Task<Void, Never>?
  private var reserveTask: Task<Void, Never>?
  private var hasStarted = false
  private var refreshRequested = false

  init(cli: DevCLI? = try? DevCLI()) {
    self.cli = cli
    startupError =
      cli == nil
      ? DevCLIError.executableNotFound.localizedDescription
      : nil
  }

  deinit {
    refreshLoop?.cancel()
    reserveTask?.cancel()
  }

  var filteredOptions: [ReservableOD] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      return reservableODs
    }
    return reservableODs.filter {
      $0.name.localizedCaseInsensitiveContains(query)
        || $0.spec.localizedCaseInsensitiveContains(query)
    }
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
  }

  func refresh() {
    if isRefreshing {
      refreshRequested = true
      return
    }
    Task {
      await refreshNow()
    }
  }

  func select(_ option: ReservableOD) {
    selectedOptionID = option.id
    UserDefaults.standard.set(
      option.id,
      forKey: Self.lastSelectedOptionKey
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

    let requestedName = sessionName
    isReserving = true
    operationError = nil
    statusMessage = "Requesting a six-day \(option.spec) reservation. Approve the Duo push."

    reserveTask = Task { [weak self] in
      guard let self else {
        return
      }
      defer {
        isReserving = false
        reserveTask = nil
      }

      let worker = Task.detached(priority: .userInitiated) {
        try cli.reserve(option: option, sessionName: requestedName)
      }
      do {
        let message = try await withTaskCancellationHandler {
          try await worker.value
        } onCancel: {
          worker.cancel()
        }
        statusMessage = message
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
        statusMessage = nil
        operationError = error.localizedDescription
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

  func setLaunchAtLoginMessage(_ message: String?) {
    launchAtLoginMessage = message
  }

  func quit() {
    NSApplication.shared.terminate(nil)
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
