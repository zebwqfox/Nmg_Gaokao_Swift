import Foundation
import Observation
import SwiftUI

enum AppRoute: Hashable {
  case article(id: String)
  case web(title: String, url: URL)
  case candidateLogin
  case studentService(StudentHomeService)
}

@MainActor
@Observable
final class RouterPath {
  var path: [AppRoute] = []

  func navigate(to route: AppRoute) {
    path.append(route)
  }

  func reset() {
    path = []
  }
}

@MainActor
@Observable
final class TabRouter {
  private var routers: [AppTab: RouterPath] = [:]

  func router(for tab: AppTab) -> RouterPath {
    if let router = routers[tab] {
      return router
    }
    let router = RouterPath()
    routers[tab] = router
    return router
  }

  func binding(for tab: AppTab) -> Binding<[AppRoute]> {
    let router = router(for: tab)
    return Binding(
      get: { router.path },
      set: { router.path = $0 }
    )
  }
}
