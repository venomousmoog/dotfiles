import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  private var store: ReservationStore?
  private var statusPanelController: StatusPanelController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.accessory)

    if CommandLine.arguments.contains("--unregister-login-item") {
      unregisterLoginItemAndExit()
      return
    }
    if CommandLine.arguments.contains("--print-login-item-status") {
      print(Self.statusName(SMAppService.mainApp.status))
      NSApplication.shared.terminate(nil)
      return
    }

    let store = ReservationStore()
    self.store = store
    UNUserNotificationCenter.current().delegate = self
    let statusPanelController = StatusPanelController(store: store)
    statusPanelController.install()
    self.statusPanelController = statusPanelController

    if CommandLine.arguments.contains("--panel-smoke-test") {
      statusPanelController.performStatusItemClickForTesting()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        let openDescription = statusPanelController.smokeDescription
        let openSucceeded = statusPanelController.smokeOpenSucceeded
        statusPanelController.performStatusItemClickForTesting()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          let toggleClosedDescription = statusPanelController.smokeDescription
          let toggleClosedSucceeded = statusPanelController.smokeClosedSucceeded
          statusPanelController.performStatusItemClickForTesting()
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let reopenedSucceeded = statusPanelController.smokeOpenSucceeded
            statusPanelController.performOutsideClickDismissalForTesting()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
              let outsideClosedDescription = statusPanelController.smokeDescription
              let outsideClosedSucceeded = statusPanelController.smokeClosedSucceeded
              print(
                "open=[\(openDescription)] toggleClosed=[\(toggleClosedDescription)] outsideClosed=[\(outsideClosedDescription)]"
              )
              if openSucceeded,
                toggleClosedSucceeded,
                reopenedSucceeded,
                outsideClosedSucceeded
              {
                NSApplication.shared.terminate(nil)
              } else {
                FileHandle.standardError.write(
                  Data(
                    "Panel smoke test failed: open=[\(openDescription)] toggleClosed=[\(toggleClosedDescription)] outsideClosed=[\(outsideClosedDescription)]\n"
                      .utf8
                  )
                )
                exit(1)
              }
            }
          }
        }
      }
      return
    }

    store.start()
    configureLaunchAtLogin()
  }

  func applicationWillTerminate(_ notification: Notification) {
    statusPanelController?.uninstall()
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  private func configureLaunchAtLogin() {
    let service = SMAppService.mainApp
    do {
      switch service.status {
      case .enabled, .requiresApproval:
        break
      case .notRegistered, .notFound:
        try service.register()
      @unknown default:
        try service.register()
      }

      switch service.status {
      case .enabled:
        store?.setLaunchAtLoginMessage(nil)
      case .requiresApproval:
        store?.setLaunchAtLoginMessage(
          "Enable DevReserve in System Settings › General › Login Items."
        )
      case .notFound, .notRegistered:
        store?.setLaunchAtLoginMessage(
          "DevReserve could not register as a login item."
        )
      @unknown default:
        store?.setLaunchAtLoginMessage(
          "DevReserve login-item status is unavailable."
        )
      }
    } catch {
      store?.setLaunchAtLoginMessage(
        "Could not enable launch at login: \(error.localizedDescription)"
      )
    }
  }

  private func unregisterLoginItemAndExit() {
    do {
      let service = SMAppService.mainApp
      if service.status == .enabled || service.status == .requiresApproval {
        try service.unregister()
      }
      print(Self.statusName(service.status))
      NSApplication.shared.terminate(nil)
    } catch {
      FileHandle.standardError.write(
        Data("Could not unregister DevReserve: \(error.localizedDescription)\n".utf8)
      )
      exit(1)
    }
  }

  private static func statusName(_ status: SMAppService.Status) -> String {
    switch status {
    case .enabled:
      return "enabled"
    case .requiresApproval:
      return "requiresApproval"
    case .notRegistered:
      return "notRegistered"
    case .notFound:
      return "notFound"
    @unknown default:
      return "unknown"
    }
  }
}

@main
struct DevReserveApp {
  @MainActor
  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
  }
}
