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
    .padding(18)
    .frame(width: 500, height: 760)
    .background {
      ZStack {
        Rectangle()
          .fill(.ultraThinMaterial)
        LinearGradient(
          colors: [
            Color.accentColor.opacity(0.10),
            Color.clear,
            Color.white.opacity(0.035),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      }
      .ignoresSafeArea()
    }
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
    HStack(spacing: 10) {
      Image(systemName: "server.rack")
        .font(.title3.weight(.semibold))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.tint)
        .frame(width: 34, height: 34)
        .background(.thinMaterial, in: Circle())
        .overlay {
          Circle()
            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
      VStack(alignment: .leading, spacing: 1) {
        Text("DevReserve")
          .font(.headline)
        Text("DevEnv reservations")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        store.refresh()
      } label: {
        Group {
          if store.isRefreshing || store.isRefreshingAgentcloud {
            ProgressView()
              .controlSize(.small)
          } else {
            Image(systemName: "arrow.clockwise")
          }
        }
        .frame(width: 16, height: 16)
      }
      .buttonStyle(.plain)
      .padding(7)
      .background(.thinMaterial, in: Circle())
      .overlay {
        Circle()
          .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
      }
      .disabled(store.isRefreshing || store.isRefreshingAgentcloud)
      .help("Refresh DevEnv inventory and Agentcloud usage")
    }
  }

  private var reservationsView: some View {
    VStack(alignment: .leading, spacing: 10) {
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
        ScrollView(.vertical, showsIndicators: false) {
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
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
        }
        .contentMargins(.horizontal, 2, for: .scrollContent)
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
      HStack {
        Text(title)
          .textCase(.uppercase)
          .tracking(0.45)
        Spacer()
        Text("\(hosts.count)")
          .monospacedDigit()
      }
      .font(.caption2.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 2)
      ForEach(hosts) { host in
        ReservationRow(
          reservation: host,
          showsExpiration: showsExpiration,
          fallbackDescription: fallbackDescription,
          allowsRelease: allowsRelease && host.releaseHostname != nil,
          isReleasing: store.releasingHostname == host.hostname,
          releaseDisabled: store.releasingHostname != nil || store.isReserving,
          agentcloudSessions: store.agentcloudSessions(using: host.hostname),
          agentcloudAttribution: store.agentcloudAttribution(for: host.hostname),
          agentcloudLease: store.agentcloudUsage.lease(for: host.hostname),
          agentcloudExpanded: store.isAgentcloudHostExpanded(host.hostname),
          terminalApplication: store.terminalApplication,
          copyHostname: {
            store.copyHostname(host.hostname)
          },
          requestRelease: {
            store.requestRelease(host)
          },
          toggleAgentcloudExpanded: {
            store.toggleAgentcloudHost(host.hostname)
          },
          openAgentcloudSession: { sessionID in
            store.openAgentcloudSession(sessionID)
          },
          openTerminal: {
            store.openTerminal(hostname: host.hostname)
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
      .frame(maxHeight: .infinity)
      .layoutPriority(1)
      .padding(6)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
      }
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
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
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
      dismissibleMessageLabel(
        error,
        systemImage: "exclamationmark.triangle.fill",
        color: .red,
        dismiss: store.dismissOperationError
      )
    } else if let error = store.refreshError {
      dismissibleMessageLabel(
        error,
        systemImage: "arrow.clockwise.circle",
        color: .orange,
        dismiss: store.dismissRefreshError
      )
    } else if let error = store.agentcloudUsageError {
      dismissibleMessageLabel(
        "Agentcloud usage unavailable: \(error)",
        systemImage: "exclamationmark.triangle.fill",
        color: .orange,
        dismiss: store.dismissAgentcloudUsageError
      )
    } else if let status = store.statusMessage {
      messageLabel(status, systemImage: "info.circle.fill", color: .secondary)
    }
  }

  @ViewBuilder
  private var loginItemMessage: some View {
    if let loginMessage = store.launchAtLoginMessage {
      dismissibleMessageLabel(
        loginMessage,
        systemImage: "gear.badge",
        color: .orange,
        dismiss: store.dismissLaunchAtLoginMessage
      )
    }
  }

  private func dismissibleMessageLabel(
    _ text: String,
    systemImage: String,
    color: Color,
    dismiss: @escaping () -> Void
  ) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Label(text, systemImage: systemImage)
        .font(.caption)
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(3)
      Button(action: dismiss) {
        Image(systemName: "xmark.circle.fill")
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Dismiss message")
    }
    .padding(9)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
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
      .padding(9)
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
      }
  }

  private var footer: some View {
    HStack {
      if let lastUpdated = store.lastUpdated {
        Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      Spacer()
      Picker("Open hosts in", selection: $store.terminalApplication) {
        ForEach(TerminalApplication.allCases) { application in
          Text(application.label).tag(application)
        }
      }
      .pickerStyle(.menu)
      .controlSize(.small)
      .fixedSize()
      .help("Choose which terminal opens host connections")
      Button("Quit") {
        store.quit()
      }
      .buttonStyle(.borderless)
    }
  }
}

private struct AgentcloudSessionRow: View {
  let session: AgentcloudSessionUsage
  let caption: String
  let openSession: (String) -> Void

  var body: some View {
    Button {
      openSession(session.id)
    } label: {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: session.running ? "bolt.circle.fill" : "circle")
          .foregroundStyle(session.running ? Color.orange : Color.secondary)
        VStack(alignment: .leading, spacing: 2) {
          Text(session.title)
            .font(.caption.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
          Text("\(caption) · \(session.id.prefix(8))")
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "arrow.up.right.square")
          .foregroundStyle(.secondary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.vertical, 6)
    .padding(.horizontal, 8)
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
  let agentcloudAttribution: AgentcloudNodeAttribution
  let agentcloudLease: AgentcloudNodeLease?
  let agentcloudExpanded: Bool
  let terminalApplication: TerminalApplication
  let copyHostname: () -> Void
  let requestRelease: () -> Void
  let toggleAgentcloudExpanded: () -> Void
  let openAgentcloudSession: (String) -> Void
  let openTerminal: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "server.rack")
        .font(.body.weight(.semibold))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.tint)
        .frame(width: 32, height: 32)
      VStack(alignment: .leading, spacing: 3) {
        Button(action: copyHostname) {
          Text(reservation.name)
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
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
        agentcloudUsage
      }
      Spacer()
      Button(action: openTerminal) {
        Image(systemName: "terminal")
          .frame(width: 14, height: 14)
      }
      .buttonStyle(.plain)
      .padding(6)
      .disabled(sshCommand(hostname: reservation.hostname) == nil)
      .help(
        sshCommand(hostname: reservation.hostname) == nil
          ? "No valid SSH hostname is available"
          : "Open in \(terminalApplication.label): \(reservation.hostname)"
      )
      .accessibilityLabel("Open \(reservation.hostname) in \(terminalApplication.label)")
      if allowsRelease {
        if isReleasing {
          ProgressView()
            .controlSize(.small)
            .help("Releasing reservation")
        } else {
          Button(action: requestRelease) {
            Image(systemName: "trash")
              .foregroundStyle(.red)
              .frame(width: 14, height: 14)
          }
          .buttonStyle(.plain)
          .padding(6)
          .disabled(releaseDisabled)
          .help("Release reservation")
          .accessibilityLabel("Release reservation")
        }
      }
    }
    .padding(12)
    .background {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color(nsColor: .textBackgroundColor))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
    }
    .shadow(color: Color.black.opacity(0.09), radius: 7, y: 3)
  }

  @ViewBuilder
  private var agentcloudUsage: some View {
    ForEach(runningSessions) { session in
      AgentcloudSessionRow(
        session: session,
        caption: "Working now",
        openSession: openAgentcloudSession
      )
    }

    if !attachedSessions.isEmpty {
      Button(action: toggleAgentcloudExpanded) {
        HStack(spacing: 5) {
          Image(systemName: "paperclip")
          Text("\(attachedSessions.count) attached")
          Image(systemName: agentcloudExpanded ? "chevron.up" : "chevron.down")
            .font(.caption2)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .padding(.vertical, 5)
      .padding(.horizontal, 8)

      if agentcloudExpanded {
        ForEach(attachedSessions) { session in
          AgentcloudSessionRow(
            session: session,
            caption: lastActivityLabel(session.lastActivityAt),
            openSession: openAgentcloudSession
          )
        }
      }
    }

    if agentcloudSessions.isEmpty {
      switch agentcloudAttribution {
      case .holder(let session, let lease):
        AgentcloudSessionRow(
          session: session ?? unresolvedHolderSession(lease.holderSessionID),
          caption: "Reserved this node",
          openSession: openAgentcloudSession
        )
      case .attached(_, _), .unknown:
        EmptyView()
      }
    }

    if let lease = agentcloudLease {
      Label(
        "\(AgentcloudLeaseText.label(expiresAt: lease.expiresAt)) · holder "
          + String(lease.holderSessionID.prefix(8)),
        systemImage: "lock.fill"
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
  }

  private var runningSessions: [AgentcloudSessionUsage] {
    AgentcloudSessionGroups(agentcloudSessions).working
  }

  private var attachedSessions: [AgentcloudSessionUsage] {
    AgentcloudSessionGroups(agentcloudSessions).attached
  }

  private func unresolvedHolderSession(_ sessionID: String) -> AgentcloudSessionUsage {
    AgentcloudSessionUsage(
      id: sessionID,
      title: String(sessionID.prefix(8)),
      running: false,
      lastActivityAt: nil,
      lastSequence: 0
    )
  }

  private func lastActivityLabel(_ date: Date?) -> String {
    guard let date else {
      return "Attached · activity unknown"
    }
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 {
      return "Last active just now"
    }
    if seconds < 3_600 {
      return "Last active \(seconds / 60)m ago"
    }
    if seconds < 86_400 {
      return "Last active \(seconds / 3_600)h ago"
    }
    return "Last active \(seconds / 86_400)d ago"
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
