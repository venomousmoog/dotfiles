import AppKit
import DevReserveCore
import SwiftUI

@MainActor
final class StatusPanelController: NSObject, NSWindowDelegate {
  private static let widthKey = "menuWindowContentWidth"
  private static let heightKey = "menuWindowContentHeight"

  private let store: ReservationStore
  private var statusItem: NSStatusItem?
  private var panel: StatusPanel?

  init(store: ReservationStore) {
    self.store = store
    super.init()
  }

  func install() {
    guard statusItem == nil else {
      return
    }

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = item.button {
      let image = NSImage(
        systemSymbolName: "server.rack",
        accessibilityDescription: "DevReserve"
      )
      image?.isTemplate = true
      button.image = image
      button.toolTip = "DevReserve"
      button.target = self
      button.action = #selector(togglePanel)
    }
    statusItem = item

    let dimensions = restoredDimensions()
    let panel = StatusPanel(
      contentRect: NSRect(
        x: 0,
        y: 0,
        width: dimensions.width,
        height: dimensions.height
      )
    )
    panel.delegate = self
    panel.contentMinSize = NSSize(
      width: WindowDimensions.minimum.width,
      height: WindowDimensions.minimum.height
    )
    panel.contentResizeIncrements = NSSize(width: 1, height: 1)

    let hostingView = NSHostingView(rootView: DevReserveView(store: store))
    hostingView.autoresizingMask = [.width, .height]
    panel.contentView = hostingView
    self.panel = panel
  }

  func uninstall() {
    if let panel {
      saveDimensions(panel.contentView?.bounds.size ?? panel.contentLayoutRect.size)
      panel.delegate = nil
      panel.orderOut(nil)
    }
    panel = nil
    if let statusItem {
      NSStatusBar.system.removeStatusItem(statusItem)
    }
    statusItem = nil
  }

  @objc private func togglePanel() {
    guard let panel else {
      return
    }
    if panel.isVisible {
      panel.orderOut(nil)
      return
    }

    applyClampedSavedSize(to: panel)
    position(panel)
    panel.makeKeyAndOrderFront(nil)
  }

  func windowDidResize(_ notification: Notification) {
    guard let panel = notification.object as? NSPanel else {
      return
    }
    saveDimensions(panel.contentView?.bounds.size ?? panel.contentLayoutRect.size)
  }

  func windowDidResignKey(_ notification: Notification) {
    guard let panel = notification.object as? NSPanel else {
      return
    }
    store.cancelRelease()
    panel.orderOut(nil)
  }

  private func restoredDimensions() -> WindowDimensions {
    let defaults = UserDefaults.standard
    guard
      defaults.object(forKey: Self.widthKey) != nil,
      defaults.object(forKey: Self.heightKey) != nil,
      let dimensions = WindowDimensions(
        width: defaults.double(forKey: Self.widthKey),
        height: defaults.double(forKey: Self.heightKey)
      )
    else {
      return .defaultValue
    }
    return dimensions
  }

  private func applyClampedSavedSize(to panel: NSPanel) {
    let dimensions = restoredDimensions()
    guard let screen = statusItem?.button?.window?.screen ?? NSScreen.main else {
      panel.setContentSize(NSSize(width: dimensions.width, height: dimensions.height))
      return
    }
    let restored = dimensions.clamped(
      maxWidth: max(
        WindowDimensions.minimum.width,
        Double(screen.visibleFrame.width) - 24
      ),
      maxHeight: max(
        WindowDimensions.minimum.height,
        Double(screen.visibleFrame.height) - 24
      )
    )
    panel.setContentSize(NSSize(width: restored.width, height: restored.height))
  }

  private func saveDimensions(_ size: NSSize) {
    guard let dimensions = WindowDimensions(width: size.width, height: size.height) else {
      return
    }
    let defaults = UserDefaults.standard
    defaults.set(dimensions.width, forKey: Self.widthKey)
    defaults.set(dimensions.height, forKey: Self.heightKey)
  }

  private func position(_ panel: NSPanel) {
    guard
      let button = statusItem?.button,
      let buttonWindow = button.window,
      let screen = buttonWindow.screen ?? NSScreen.main
    else {
      panel.center()
      return
    }

    let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
    let visibleFrame = screen.visibleFrame
    let panelSize = panel.frame.size
    let margin: CGFloat = 8

    var x = buttonFrame.midX - (panelSize.width / 2)
    x = min(
      max(x, visibleFrame.minX + margin),
      visibleFrame.maxX - panelSize.width - margin
    )

    var y = buttonFrame.minY - panelSize.height - 4
    if y < visibleFrame.minY + margin {
      y = buttonFrame.maxY + 4
    }
    y = min(
      max(y, visibleFrame.minY + margin),
      visibleFrame.maxY - panelSize.height - margin
    )

    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }
}

private final class StatusPanel: NSPanel {
  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.titled, .fullSizeContentView, .resizable, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    title = "DevReserve"
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true
    isMovable = false
    isMovableByWindowBackground = false
    isReleasedWhenClosed = false
    isFloatingPanel = true
    hidesOnDeactivate = true
    level = .popUpMenu
    collectionBehavior = [.transient, .moveToActiveSpace]
    animationBehavior = .utilityWindow
    backgroundColor = .clear
    isOpaque = false
    hasShadow = true
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
