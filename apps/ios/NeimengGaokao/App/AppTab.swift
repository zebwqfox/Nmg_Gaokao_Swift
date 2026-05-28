import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Hashable {
  case dashboard
  case services
  case content
  case calendar
  case settings

  var id: String { rawValue }

  @ViewBuilder
  var rootView: some View {
    switch self {
    case .dashboard:
      DashboardView()
    case .services:
      ServicesView()
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
    case .dashboard:
      Label("工作台", systemImage: "house")
    case .services:
      Label("服务", systemImage: "square.grid.2x2")
    case .content:
      Label("资讯", systemImage: "newspaper")
    case .calendar:
      Label("日历", systemImage: "calendar")
    case .settings:
      Label("我的", systemImage: "person.crop.circle")
    }
  }
}
