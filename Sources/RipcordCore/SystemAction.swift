import Foundation

/// The system commands Raycast calls System Actions, found by typing like Ripcord's own.
public enum SystemAction: String, CaseIterable, Sendable {
  // Raw values are the settings keys' stable part, spelled out so a rename never strands them.
  case lockScreen = "lock-screen"
  case logOut = "log-out"
  case restart = "restart"
  case shutDown = "shut-down"
  case sleep = "sleep"
  case sleepDisplays = "sleep-displays"
  case showScreenSaver = "show-screen-saver"
  case playPause = "play-pause"
  case nextTrack = "next-track"
  case previousTrack = "previous-track"
  case toggleMute = "toggle-mute"
  case volumeUp = "volume-up"
  case volumeDown = "volume-down"
  case setVolume = "set-volume"
  case setVolume0 = "set-volume-0"
  case setVolume25 = "set-volume-25"
  case setVolume50 = "set-volume-50"
  case setVolume75 = "set-volume-75"
  case setVolume100 = "set-volume-100"
  case hideOtherApps = "hide-other-apps"
  case unhideAllApps = "unhide-all-apps"
  case quitAllApps = "quit-all-apps"
  case quitOtherApps = "quit-other-apps"
  case restartFrontmostApp = "restart-frontmost-app"
  case openTrash = "open-trash"
  case emptyTrash = "empty-trash"
  case ejectAllDisks = "eject-all-disks"
  case showDesktop = "show-desktop"
  case toggleAppearance = "toggle-appearance"
  case toggleHiddenFiles = "toggle-hidden-files"

  /// Raycast's Set Volume to 0%, 25%, 50%, 75% and 100%: the level each sets.
  public var volumePercent: Int? {
    switch self {
    case .setVolume0: 0
    case .setVolume25: 25
    case .setVolume50: 50
    case .setVolume75: 75
    case .setVolume100: 100
    default: nil
    }
  }

  /// Set Volume's level typed after it, as "40" or "40%"; nil for anything else or past 100.
  public static func volumePercent(from text: String) -> Int? {
    var digits = text.trimmingCharacters(in: .whitespaces)
    if digits.hasSuffix("%") { digits.removeLast() }
    guard let value = Int(digits), (0...100).contains(value) else { return nil }
    return value
  }

  public var title: String {
    switch self {
    case .lockScreen: "Lock Screen"
    case .logOut: "Log Out"
    case .restart: "Restart"
    case .shutDown: "Shut Down"
    case .sleep: "Sleep"
    case .sleepDisplays: "Sleep Displays"
    case .showScreenSaver: "Show Screen Saver"
    case .playPause: "Play / Pause"
    case .nextTrack: "Next Track"
    case .previousTrack: "Previous Track"
    case .toggleMute: "Toggle Mute"
    case .volumeUp: "Turn Volume Up"
    case .volumeDown: "Turn Volume Down"
    case .setVolume: "Set Volume"
    case .setVolume0, .setVolume25, .setVolume50, .setVolume75, .setVolume100:
      "Set Volume to \(volumePercent ?? 0)%"
    case .hideOtherApps: "Hide All Apps Except Frontmost"
    case .unhideAllApps: "Unhide All Hidden Apps"
    case .quitAllApps: "Quit All Apps"
    case .quitOtherApps: "Quit All Apps Except Frontmost"
    case .restartFrontmostApp: "Restart Frontmost App"
    case .openTrash: "Open Trash"
    case .emptyTrash: "Empty Trash"
    case .ejectAllDisks: "Eject All Disks"
    case .showDesktop: "Show Desktop"
    case .toggleAppearance: "Toggle System Appearance"
    case .toggleHiddenFiles: "Toggle Hidden Files"
    }
  }

  public var settingsKey: String { "system:\(rawValue)" }

  /// What's asked first, for the ones that lose work or end the session; nil runs at once.
  public var warning: String? {
    switch self {
    case .logOut: "Apps will quit, and unsaved work may be lost."
    case .restart: "Apps will quit and the Mac will restart."
    case .shutDown: "Apps will quit and the Mac will shut down."
    case .emptyTrash: "Everything in the Trash will be deleted. This can't be undone."
    case .quitAllApps: "Every open app will be asked to quit."
    case .quitOtherApps: "Every open app but the frontmost one will be asked to quit."
    default: nil
    }
  }
}

/// The settings Raycast keeps inside Empty Trash, Quit All Apps and Quit All Apps Except
/// Frontmost: whether each asks first, and the apps each Quit All leaves open.
public struct SystemActionSettings: Codable, Equatable, Sendable {
  public var warnBeforeEmptyingTrash: Bool
  public var warnBeforeQuittingAll: Bool
  /// Bundle IDs Quit All Apps leaves open.
  public var quitAllExcluded: [String]
  public var warnBeforeQuittingOthers: Bool
  /// Bundle IDs Quit All Apps Except Frontmost leaves open.
  public var quitOthersExcluded: [String]

  public init(
    warnBeforeEmptyingTrash: Bool = true, warnBeforeQuittingAll: Bool = true,
    quitAllExcluded: [String] = [], warnBeforeQuittingOthers: Bool = true,
    quitOthersExcluded: [String] = []
  ) {
    self.warnBeforeEmptyingTrash = warnBeforeEmptyingTrash
    self.warnBeforeQuittingAll = warnBeforeQuittingAll
    self.quitAllExcluded = quitAllExcluded
    self.warnBeforeQuittingOthers = warnBeforeQuittingOthers
    self.quitOthersExcluded = quitOthersExcluded
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    func flag(_ key: CodingKeys) throws -> Bool {
      try container.decodeIfPresent(Bool.self, forKey: key) ?? true
    }
    func apps(_ key: CodingKeys) throws -> [String] {
      try container.decodeIfPresent([String].self, forKey: key) ?? []
    }
    self.init(
      warnBeforeEmptyingTrash: try flag(.warnBeforeEmptyingTrash),
      warnBeforeQuittingAll: try flag(.warnBeforeQuittingAll),
      quitAllExcluded: try apps(.quitAllExcluded),
      warnBeforeQuittingOthers: try flag(.warnBeforeQuittingOthers),
      quitOthersExcluded: try apps(.quitOthersExcluded))
  }

  /// Whether `action` asks before it runs: its warning, unless turned off here.
  public func asksFirst(_ action: SystemAction) -> Bool {
    guard action.warning != nil else { return false }
    switch action {
    case .emptyTrash: return warnBeforeEmptyingTrash
    case .quitAllApps: return warnBeforeQuittingAll
    case .quitOtherApps: return warnBeforeQuittingOthers
    default: return true
    }
  }

  /// Whether `action` leaves the app with `bundleID` open: Finder always, as before, and the
  /// apps excluded for that action.
  public func keepsOpen(_ bundleID: String?, for action: SystemAction) -> Bool {
    guard let bundleID else { return false }
    if bundleID == "com.apple.finder" { return true }
    switch action {
    case .quitAllApps: return quitAllExcluded.contains(bundleID)
    case .quitOtherApps: return quitOthersExcluded.contains(bundleID)
    default: return false
    }
  }
}
