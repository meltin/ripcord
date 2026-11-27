import Foundation

/// Lid Awake while it's on: when it turns itself off, or nil until it's turned off.
public struct LidAwakeStatus: Equatable, Sendable {
  public let endsAt: Date?
  public init(endsAt: Date?) { self.endsAt = endsAt }
}

extension Search {
  /// While Lid Awake is on, a row at the top of the root search saying so and how long is left,
  /// whose Return turns it off.
  public static func lidAwakeSection(_ status: LidAwakeStatus?, now: Date = .now) -> SearchSection?
  {
    guard let status else { return nil }
    let left =
      status.endsAt.map {
        "\(Coffee.format(max(0, $0.timeIntervalSince(now)), seconds: false)) left"
      }
      ?? "Until turned off"
    var row = SearchResult(
      id: "lid-awake-on", title: "Lid Awake Is On", subtitle: left, keyword: nil, kind: .command,
      action: .stopLidAwake)
    row.menu = [
      MenuAction(title: "Turn Off Lid Awake", symbol: "moon", shortcut: "↵", action: .stopLidAwake)
    ]
    return SearchSection(title: "Lid Awake", results: [row])
  }
}

/// The battery as macOS reports it, for Lid Awake to turn itself off before it runs out.
public struct BatteryLevel: Equatable, Sendable {
  public let percent: Int
  public let onBattery: Bool
  public init(percent: Int, onBattery: Bool) {
    self.percent = percent
    self.onBattery = onBattery
  }

  /// Whether Lid Awake should give up at `limit` percent; 0 never does.
  public func isLow(below limit: Int) -> Bool { onBattery && limit > 0 && percent <= limit }
}
