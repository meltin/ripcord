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
