import AppIntents
import Foundation

/// What the lock-screen "Favourite song" control and the app share. Compiled into both targets: the app writes
/// the current song's star state into the App Group, and the control (MuslyWidgets) reads it to draw its star.
enum FavoriteControlState {
  static let appGroup = "group.com.kallewoof.musly"
  static let controlKind = "com.kallewoof.musly.favorite-control"
  static let starredKey = "favoriteControl.starred"
  static let toggleRequested = Notification.Name("MuslyFavoriteControlToggle")

  static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }
}

/// An AudioPlaybackIntent runs in the app's process (seen on iOS 26 with a probe app), so a press reaches the
/// running player rather than the widget extension, which holds no player and no login.
@available(iOS 17.0, *)
struct ToggleFavoriteIntent: AudioPlaybackIntent {
  static var title: LocalizedStringResource = "Favourite current song"

  func perform() async throws -> some IntentResult {
    await MainActor.run {
      NotificationCenter.default.post(name: FavoriteControlState.toggleRequested, object: nil)
    }
    return .result()
  }
}
