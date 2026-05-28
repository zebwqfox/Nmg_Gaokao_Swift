import SwiftData
import SwiftUI

@main
struct NeimengGaokaoApp: App {
  var body: some Scene {
    WindowGroup {
      AppView()
    }
    .modelContainer(for: [
      CachedArticle.self,
      CachedCategory.self,
      CachedServiceLink.self,
      CandidateProfile.self
    ])
  }
}

