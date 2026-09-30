import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let store = ReservationStore()

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

    store.start()
    configureLaunchAtLogin()
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
        store.setLaunchAtLoginMessage(nil)
      case .requiresApproval:
        store.setLaunchAtLoginMessage(
          "Enable DevReserve in System Settings › General › Login Items."
        )
      case .notFound, .notRegistered:
        store.setLaunchAtLoginMessage(
          "DevReserve could not register as a login item."
        )
      @unknown default:
        store.setLaunchAtLoginMessage(
          "DevReserve login-item status is unavailable."
        )
      }
    } catch {
      store.setLaunchAtLoginMessage(
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
struct DevReserveApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra("DevReserve", systemImage: "server.rack") {
      DevReserveView(store: appDelegate.store)
    }
    .menuBarExtraStyle(.window)
  }
}
