import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Hashable {
  case content
  case search
  case calendar
  case settings

  var id: String { rawValue }

  @ViewBuilder
  var rootView: some View {
    switch self {
    case .content:
      ContentFeedView()
    case .search:
      ContentSearchView()
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
    case .search:
      Label("搜索", systemImage: "magnifyingglass")
    case .calendar:
      Label("日历", systemImage: "calendar")
    case .settings:
      Label("我的", systemImage: "person.crop.circle")
    }
  }
}
