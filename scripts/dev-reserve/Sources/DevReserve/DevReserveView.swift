import AppKit
import DevReserveCore
import SwiftUI

struct DevReserveView: View {
  @ObservedObject var store: ReservationStore

  var body: some View {
    VStack(spacing: 14) {
      header
      Picker("Surface", selection: $store.surface) {
        ForEach(ReservationStore.Surface.allCases) { surface in
          Text(surface.rawValue).tag(surface)
        }
      }
      .labelsHidden()
      .pickerStyle(.segmented)

      Group {
        switch store.surface {
        case .reservations:
          reservationsView
        case .reserve:
          reserveView
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      messages
      loginItemMessage
      footer
    }
    .padding(16)
    .frame(width: 460, height: 590)
    .confirmationDialog(
      "Release reservation?",
      isPresented: Binding(
        get: { store.pendingRelease != nil },
        set: { isPresented in
          if !isPresented {
            store.cancelRelease()
          }
        }
      ),
      titleVisibility: .visible,
      presenting: store.pendingRelease
    ) { reservation in
      Button("Release \(reservation.hostname)", role: .destructive) {
        store.confirmRelease(reservation)
      }
      Button("Cancel", role: .cancel) {
        store.cancelRelease()
      }
    } message: { reservation in
      Text("This immediately releases \(reservation.name). This action cannot be undone.")
    }
  }

  private var header: some View {
    HStack {
      Label("DevReserve", systemImage: "server.rack")
        .font(.headline)
      Spacer()
      Button {
        store.refresh()
      } label: {
        if store.isRefreshing || store.isRefreshingAgentcloud {
          ProgressView()
            .controlSize(.small)
        } else {
          Image(systemName: "arrow.clockwise")
        }
      }
      .buttonStyle(.borderless)
      .disabled(store.isRefreshing || store.isRefreshingAgentcloud)
      .help("Refresh DevEnv inventory")
    }
  }

  private var reservationsView: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Hosts")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text("\(store.reservations.count + store.shortTermLeases.count + store.devservers.count)")
          .foregroundStyle(.secondary)
      }

      if store.isRefreshing && store.reservations.isEmpty && store.shortTermLeases.isEmpty
        && store.devservers.isEmpty
      {
        Spacer()
        ProgressView("Loading DevEnv inventory…")
          .frame(maxWidth: .infinity)
        Spacer()
      } else if store.reservations.isEmpty && store.shortTermLeases.isEmpty
        && store.devservers.isEmpty
      {
        ContentUnavailableView(
          "No hosts found",
          systemImage: "server.rack",
          description: Text("Reserve an OD from the Reserve tab.")
        )
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 10) {
            hostSection(
              title: "Active OD reservations",
              hosts: store.reservations,
              showsExpiration: true,
              fallbackDescription: "Expiration unavailable",
              allowsRelease: true
            )
            hostSection(
              title: "Short-term devserver leases",
              hosts: store.shortTermLeases,
              showsExpiration: false,
              fallbackDescription: "Short-term Devserver V2 lease",
              allowsRelease: false
            )
            hostSection(
              title: "Devservers",
              hosts: store.devservers,
              showsExpiration: false,
              fallbackDescription: "Long-lived devserver",
              allowsRelease: false
            )
          }
        }
      }
    }
  }

  @ViewBuilder
  private func hostSection(
    title: String,
    hosts: [DevReservation],
    showsExpiration: Bool,
    fallbackDescription: String,
    allowsRelease: Bool
  ) -> some View {
    if !hosts.isEmpty {
      Text("\(title) · \(hosts.count)")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      ForEach(hosts) { host in
        ReservationRow(
          reservation: host,
          showsExpiration: showsExpiration,
          fallbackDescription: fallbackDescription,
          allowsRelease: allowsRelease && host.releaseHostname != nil,
          isReleasing: store.releasingHostname == host.hostname,
          releaseDisabled: store.releasingHostname != nil || store.isReserving,
          agentcloudSessions: store.agentcloudSessions(using: host.hostname),
          agentcloudUsageSummary: store.agentcloudUsageSummary(for: host.hostname),
          copyHostname: {
            store.copyHostname(host.hostname)
          },
          requestRelease: {
            store.requestRelease(host)
          }
        )
      }
    }
  }

  private var reserveView: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(
        "Choose 1, 2, 3, or 6 days, then approve the Duo push. DevEnv owns the lease after allocation.",
        systemImage: "calendar.badge.clock"
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      TextField("Search OD types", text: $store.searchText)
        .textFieldStyle(.roundedBorder)

      ScrollView {
        LazyVStack(spacing: 4) {
          ForEach(store.filteredOptions) { option in
            ReservableRow(
              option: option,
              selected: option.id == store.selectedOptionID,
              favorite: store.isFavorite(option),
              select: { store.select(option) },
              toggleFavorite: { store.toggleFavorite(option) }
            )
          }
        }
      }
      .frame(maxHeight: 270)
      .overlay {
        if store.filteredOptions.isEmpty && !store.isRefreshing {
          ContentUnavailableView.search(text: store.searchText)
        }
      }

      if let option = store.selectedOption {
        VStack(alignment: .leading, spacing: 4) {
          Text(option.name)
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
          Text(option.spec)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
          if let hardware = option.hardwareOption {
            Text("Hardware: \(hardware)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      Picker("Reservation duration", selection: $store.reservationDuration) {
        ForEach(ReservationDuration.allCases) { duration in
          Text(duration.label).tag(duration)
        }
      }
      .pickerStyle(.segmented)

      TextField("Optional session name", text: $store.sessionName)
        .textFieldStyle(.roundedBorder)
      if !store.sessionNameIsValid {
        Text("Use only letters, numbers, and underscores, up to 64 characters.")
          .font(.caption)
          .foregroundStyle(.red)
      }

      if store.isReserving {
        Button {
          store.cancelReservation()
        } label: {
          HStack {
            ProgressView()
              .controlSize(.small)
            Text("Stop waiting")
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
      } else {
        Button {
          store.reserveSelected()
        } label: {
          Text("Reserve for \(store.reservationDuration.label)")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          store.selectedOption == nil
            || !store.sessionNameIsValid
            || store.releasingHostname != nil
        )
      }
    }
  }

  @ViewBuilder
  private var messages: some View {
    if let error = store.operationError {
      messageLabel(error, systemImage: "exclamationmark.triangle.fill", color: .red)
    } else if let error = store.refreshError {
      messageLabel(error, systemImage: "arrow.clockwise.circle", color: .orange)
    } else if let status = store.statusMessage {
      messageLabel(status, systemImage: "info.circle.fill", color: .secondary)
    }
  }

  @ViewBuilder
  private var loginItemMessage: some View {
    if let loginMessage = store.launchAtLoginMessage {
      messageLabel(loginMessage, systemImage: "gear.badge", color: .orange)
    }
  }

  private func messageLabel(
    _ text: String,
    systemImage: String,
    color: Color
  ) -> some View {
    Label(text, systemImage: systemImage)
      .font(.caption)
      .foregroundStyle(color)
      .frame(maxWidth: .infinity, alignment: .leading)
      .lineLimit(3)
  }

  private var footer: some View {
    HStack {
      if let lastUpdated = store.lastUpdated {
        Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      Spacer()
      Button("Quit") {
        store.quit()
      }
      .buttonStyle(.borderless)
    }
  }
}

private struct ReservationRow: View {
  let reservation: DevReservation
  let showsExpiration: Bool
  let fallbackDescription: String
  let allowsRelease: Bool
  let isReleasing: Bool
  let releaseDisabled: Bool
  let agentcloudSessions: [AgentcloudSessionUsage]
  let agentcloudUsageSummary: String
  let copyHostname: () -> Void
  let requestRelease: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "server.rack")
        .foregroundStyle(.tint)
        .frame(width: 20)
      VStack(alignment: .leading, spacing: 3) {
        Button(action: copyHostname) {
          Text(reservation.name)
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .help("Click to copy \(reservation.hostname).\n\n\(agentcloudUsageSummary)")
        .accessibilityLabel("Copy \(reservation.hostname)")
        Text(reservation.hostname)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
        if showsExpiration {
          HStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
              Text(
                ExpirationText.relative(
                  expiration: reservation.expiresAt,
                  now: context.date
                )
              )
              .foregroundStyle(expirationColor(at: context.date))
            }
            Text("·")
            Text(ExpirationText.absolute(reservation.expiresAt))
              .foregroundStyle(.secondary)
          }
          .font(.caption)
        } else {
          Text(fallbackDescription)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if !agentcloudSessions.isEmpty {
          Label(
            "\(agentcloudSessions.count) Agentcloud "
              + (agentcloudSessions.count == 1 ? "session" : "sessions") + " running",
            systemImage: "bolt.horizontal.circle"
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
          .help(agentcloudUsageSummary)
        }
      }
      Spacer()
      if allowsRelease {
        if isReleasing {
          ProgressView()
            .controlSize(.small)
            .help("Releasing reservation")
        } else {
          Button(action: requestRelease) {
            Image(systemName: "trash")
              .foregroundStyle(.red)
          }
          .buttonStyle(.borderless)
          .disabled(releaseDisabled)
          .help("Release reservation")
          .accessibilityLabel("Release reservation")
        }
      }
    }
    .padding(10)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    .help(agentcloudUsageSummary)
  }

  private func expirationColor(at date: Date) -> Color {
    guard let expiresAt = reservation.expiresAt else {
      return .secondary
    }
    return expiresAt.timeIntervalSince(date) < 3_600 ? .red : .secondary
  }
}

private struct ReservableRow: View {
  let option: ReservableOD
  let selected: Bool
  let favorite: Bool
  let select: () -> Void
  let toggleFavorite: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Button(action: select) {
        HStack(spacing: 8) {
          Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
          VStack(alignment: .leading, spacing: 2) {
            Text(option.name)
              .lineLimit(1)
            HStack(spacing: 6) {
              Text(option.spec)
                .font(.caption.monospaced())
              Text(option.status)
                .font(.caption)
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
          }
          Spacer()
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)

      Button(action: toggleFavorite) {
        Image(systemName: favorite ? "star.fill" : "star")
          .foregroundStyle(favorite ? Color.yellow : Color.secondary)
      }
      .buttonStyle(.borderless)
      .help(favorite ? "Remove from favorites" : "Add to favorites")
      .accessibilityLabel(favorite ? "Remove from favorites" : "Add to favorites")
    }
    .padding(.vertical, 5)
    .padding(.horizontal, 6)
    .background(
      selected ? Color.accentColor.opacity(0.12) : Color.clear,
      in: RoundedRectangle(cornerRadius: 7)
    )
  }
}
