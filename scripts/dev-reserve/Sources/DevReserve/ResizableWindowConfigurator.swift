import AppKit
import DevReserveCore
import SwiftUI

struct ResizableWindowConfigurator: NSViewRepresentable {
  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> WindowReaderView {
    let view = WindowReaderView()
    view.onWindowAvailable = { [weak coordinator = context.coordinator] window in
      coordinator?.configure(window)
    }
    return view
  }

  func updateNSView(_ nsView: WindowReaderView, context: Context) {
    if let window = nsView.window {
      context.coordinator.configure(window)
    }
  }

  static func dismantleNSView(_ nsView: WindowReaderView, coordinator: Coordinator) {
    nsView.onWindowAvailable = nil
    coordinator.disconnect()
  }

  final class WindowReaderView: NSView {
    var onWindowAvailable: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let window {
        onWindowAvailable?(window)
      }
    }
  }

  @MainActor
  final class Coordinator: NSObject {
    private static let widthKey = "menuWindowContentWidth"
    private static let heightKey = "menuWindowContentHeight"

    private weak var configuredWindow: NSWindow?

    func configure(_ window: NSWindow) {
      guard configuredWindow !== window else {
        return
      }
      disconnect()
      configuredWindow = window

      window.styleMask.insert(.resizable)
      window.contentMinSize = NSSize(
        width: WindowDimensions.minimum.width,
        height: WindowDimensions.minimum.height
      )
      window.contentResizeIncrements = NSSize(width: 1, height: 1)

      let dimensions = savedDimensions() ?? .defaultValue
      let visibleSize = window.screen?.visibleFrame.size ?? NSScreen.main?.visibleFrame.size
      let visibleWidth = visibleSize.map { Double($0.width) } ?? dimensions.width
      let visibleHeight = visibleSize.map { Double($0.height) } ?? dimensions.height
      let restored = dimensions.clamped(
        maxWidth: max(
          WindowDimensions.minimum.width,
          visibleWidth - 24
        ),
        maxHeight: max(
          WindowDimensions.minimum.height,
          visibleHeight - 24
        )
      )
      window.setContentSize(NSSize(width: restored.width, height: restored.height))

      NotificationCenter.default.addObserver(
        self,
        selector: #selector(windowDidResize(_:)),
        name: NSWindow.didResizeNotification,
        object: window
      )
    }

    func disconnect() {
      if let configuredWindow {
        save(window: configuredWindow)
        NotificationCenter.default.removeObserver(
          self,
          name: NSWindow.didResizeNotification,
          object: configuredWindow
        )
      }
      configuredWindow = nil
    }

    @objc private func windowDidResize(_ notification: Notification) {
      guard let window = notification.object as? NSWindow else {
        return
      }
      save(window: window)
    }

    private func savedDimensions() -> WindowDimensions? {
      let defaults = UserDefaults.standard
      guard
        defaults.object(forKey: Self.widthKey) != nil,
        defaults.object(forKey: Self.heightKey) != nil
      else {
        return nil
      }
      return WindowDimensions(
        width: defaults.double(forKey: Self.widthKey),
        height: defaults.double(forKey: Self.heightKey)
      )
    }

    private func save(window: NSWindow) {
      let size = window.contentView?.bounds.size ?? window.contentLayoutRect.size
      guard let dimensions = WindowDimensions(width: size.width, height: size.height) else {
        return
      }
      let defaults = UserDefaults.standard
      defaults.set(dimensions.width, forKey: Self.widthKey)
      defaults.set(dimensions.height, forKey: Self.heightKey)
    }

    deinit {
      NotificationCenter.default.removeObserver(self)
    }
  }
}
