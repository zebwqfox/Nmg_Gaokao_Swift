import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Hashable {
  case content
  case calendar
  case settings

  var id: String { rawValue }

  @ViewBuilder
  var rootView: some View {
    switch self {
    case .content:
      ContentFeedView()
    case .calendar:
      CalendarView()
    case .settings:
      SettingsView()
    }
  }

  @ViewBuilder
  var label: some View {
    switch self {
    case .content:
      Label("资讯", systemImage: "newspaper")
    case .calendar:
      Label("日历", systemImage: "calendar")
    case .settings:
      Label("我的", systemImage: "person.crop.circle")
    }
  }
}
