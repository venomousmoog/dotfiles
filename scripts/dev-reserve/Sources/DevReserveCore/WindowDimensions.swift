import Foundation

public struct WindowDimensions: Equatable, Sendable {
  public static let defaultValue = WindowDimensions(uncheckedWidth: 500, height: 760)
  public static let minimum = WindowDimensions(uncheckedWidth: 460, height: 620)

  public let width: Double
  public let height: Double

  public init?(width: Double, height: Double) {
    guard
      width.isFinite,
      height.isFinite,
      width >= Self.minimum.width,
      height >= Self.minimum.height
    else {
      return nil
    }
    self.width = width
    self.height = height
  }

  public func clamped(maxWidth: Double, maxHeight: Double) -> WindowDimensions {
    let usableWidth = max(Self.minimum.width, maxWidth)
    let usableHeight = max(Self.minimum.height, maxHeight)
    return WindowDimensions(
      uncheckedWidth: min(width, usableWidth),
      height: min(height, usableHeight)
    )
  }

  private init(uncheckedWidth width: Double, height: Double) {
    self.width = width
    self.height = height
  }
}
