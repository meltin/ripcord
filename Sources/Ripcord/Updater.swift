import AppKit
import Sparkle

/// Updates from GitHub releases through Sparkle: Check for Updates, and a daily check while
/// it's on. A copy Nix installed has none: Nix updates it, and its store is read-only.
@MainActor
@Observable
final class Updater: NSObject {
  /// Nil under Nix, and in a bare `swift run`, which has no bundle to update.
  @ObservationIgnored private var controller: SPUStandardUpdaterController?

  /// Kept by Sparkle in Ripcord's defaults; on until turned off (SUEnableAutomaticChecks).
  var checksAutomatically = false {
    didSet { controller?.updater.automaticallyChecksForUpdates = checksAutomatically }
  }

  var isAvailable: Bool { controller != nil }

  override init() {
    super.init()
    // Followed through links, as `nix profile` installs one in ~/.nix-profile/Applications.
    guard !Bundle.main.bundleURL.resolvingSymlinksInPath().path.hasPrefix("/nix/store/"),
      Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
    else { return }
    let controller = SPUStandardUpdaterController(
      startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    self.controller = controller
    checksAutomatically = controller.updater.automaticallyChecksForUpdates
  }

  func checkForUpdates() {
    guard let controller else {
      let alert = NSAlert()
      alert.messageText = "Nix keeps this copy of Ripcord up to date."
      alert.informativeText = "Update it the way you installed it, with Nix."
      NSApp.activate()
      alert.runModal()
      return
    }
    // An accessory app's windows come forward only once it's active.
    NSApp.activate()
    controller.checkForUpdates(nil)
  }
}

extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
  /// Ripcord runs in the background, where Sparkle would otherwise show an update behind the app
  /// the user is in; one found on a scheduled check is brought forward as it's shown.
  var supportsGentleScheduledUpdateReminders: Bool { true }

  func standardUserDriverWillHandleShowingUpdate(
    _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
  ) {
    guard handleShowingUpdate, !state.userInitiated else { return }
    NSApp.activate()
  }
}
