import AppIntents
import SwiftUI
import WidgetKit

@main
struct MuslyWidgets: WidgetBundle {
  var body: some Widget {
    FavoriteControl()
  }
}

/// A Lock Screen and Control Center button showing whether the song Musly is playing is starred; pressing it
/// stars or unstars that song.
struct FavoriteControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: FavoriteControlState.controlKind, provider: Provider()) { starred in
      ControlWidgetButton(action: ToggleFavoriteIntent()) {
        Label(starred ? "Favourite" : "Not favourite", systemImage: starred ? "star.fill" : "star")
      }
    }
    .displayName("Favourite song")
    .description("Stars or unstars the song Musly is playing.")
  }

  struct Provider: ControlValueProvider {
    var previewValue: Bool { true }

    func currentValue() async throws -> Bool {
      FavoriteControlState.defaults?.bool(forKey: FavoriteControlState.starredKey) ?? false
    }
  }
}
