import AppKit
import DevReserveCore
import Foundation
import UserNotifications

@MainActor
final class ReservationNotifier {
  private let center = UNUserNotificationCenter.current()
  private var authorizationTask: Task<Void, Never>?

  func requestAuthorization() {
    guard authorizationTask == nil else {
      return
    }
    authorizationTask = Task {
      let settings = await center.notificationSettings()
      guard settings.authorizationStatus == .notDetermined else {
        return
      }
      _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }
  }

  func reservationSucceeded(
    optionName: String,
    duration: ReservationDuration
  ) {
    deliver(
      title: "DevReserve reservation succeeded",
      body: "\(optionName) was reserved for \(duration.label). Open DevReserve for details."
    )
  }

  func reservationFailed(
    optionName: String,
    duration: ReservationDuration
  ) {
    deliver(
      title: "DevReserve reservation failed",
      body: "The \(duration.label) request for \(optionName) failed. Open DevReserve for details."
    )
  }

  private func deliver(title: String, body: String) {
    requestAuthorization()
    let pendingAuthorization = authorizationTask

    Task {
      await pendingAuthorization?.value
      authorizationTask = nil

      let settings = await center.notificationSettings()
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "DevReserveReservations"
        let request = UNNotificationRequest(
          identifier: UUID().uuidString,
          content: content,
          trigger: nil
        )
        do {
          try await center.add(request)
        } catch {
          NSApplication.shared.requestUserAttention(.informationalRequest)
        }
      case .denied, .notDetermined:
        NSApplication.shared.requestUserAttention(.informationalRequest)
      @unknown default:
        NSApplication.shared.requestUserAttention(.informationalRequest)
      }
    }
  }
}
