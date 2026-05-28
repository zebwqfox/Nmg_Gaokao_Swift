import SwiftUI

struct AppView: View {
  @State private var selectedTab: AppTab = .dashboard
  @State private var router = TabRouter()

  var body: some View {
    TabView(selection: $selectedTab) {
      ForEach(AppTab.allCases) { tab in
        NavigationStack(path: router.binding(for: tab)) {
          tab.rootView
            .navigationDestination(for: AppRoute.self) { route in
              RouteView(route: route)
            }
        }
        .environment(router.router(for: tab))
        .tabItem { tab.label }
        .tag(tab)
      }
    }
    .withAppDependencies()
  }
}

private struct RouteView: View {
  let route: AppRoute

  var body: some View {
    switch route {
    case .article(let id):
      ArticleDetailView(articleID: id)
    case .web(let title, let url):
      ManagedWebView(title: title, url: url)
    case .candidateLogin:
      CandidateLoginView()
    case .studentService(let service):
      StudentServiceNativeView(service: service)
    }
  }
}
