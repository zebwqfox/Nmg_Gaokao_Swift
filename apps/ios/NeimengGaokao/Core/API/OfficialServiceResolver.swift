import Foundation

struct OfficialServiceResolver {
  static let defaultPlanCode = "202610010001"

  func launchURL(
    for homeService: StudentHomeService,
    token: String?,
    officialServices: [OfficialStudentService] = []
  ) -> URL {
    if let matched = matchOfficialService(for: homeService, in: officialServices) {
      return matched.launchURL(token: token)
    }
    return homeService.fallbackURL(planCode: Self.defaultPlanCode, token: token)
  }

  func launchURL(
    for catalogService: OfficialService,
    token: String?,
    officialServices: [OfficialStudentService] = []
  ) -> URL {
    if let matched = matchOfficialService(title: catalogService.title, keywords: [catalogService.title], in: officialServices) {
      return matched.launchURL(token: token)
    }
    return catalogService.url
  }

  func matchOfficialService(
    for homeService: StudentHomeService,
    in officialServices: [OfficialStudentService]
  ) -> OfficialStudentService? {
    matchOfficialService(title: homeService.title, keywords: homeService.matchKeywords, in: officialServices)
  }

  func matchOfficialService(
    title: String,
    keywords: [String],
    in officialServices: [OfficialStudentService]
  ) -> OfficialStudentService? {
    officialServices.max { lhs, rhs in
      matchScore(for: lhs, title: title, keywords: keywords) < matchScore(for: rhs, title: title, keywords: keywords)
    }
    .flatMap { service in
      matchScore(for: service, title: title, keywords: keywords) > 0 ? service : nil
    }
  }

  static func systemTotalURL(source: String, planCode: String, token: String? = nil) -> URL {
    var components = URLComponents(string: "https://www4.nm.zsks.cn/BaseStudent/systemTotal")!
    components.queryItems = [
      URLQueryItem(name: "src", value: source),
      URLQueryItem(name: "planCode", value: planCode)
    ]
    guard let url = components.url else {
      return OfficialServiceCatalog.studentPortal
    }
    return url.appendingOfficialQuery(planCode: nil, token: token)
  }

  private func matchScore(for service: OfficialStudentService, title: String, keywords: [String]) -> Int {
    let name = service.name ?? ""
    guard !name.isEmpty else { return 0 }

    var score = 0
    if name == title { score += 100 }
    if name.contains(title) || title.contains(name) { score += 40 }

    for keyword in keywords where name.localizedCaseInsensitiveContains(keyword) {
      score += 25
    }
    if let type = service.type, keywords.contains(where: { type.localizedCaseInsensitiveContains($0) }) {
      score += 10
    }
    return score
  }
}

private extension URL {
  func appendingOfficialQuery(planCode: String?, token: String?) -> URL {
    guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
      return self
    }
    var items = components.queryItems ?? []
    if let planCode, !planCode.isEmpty, !items.contains(where: { $0.name == "planCode" }) {
      items.append(URLQueryItem(name: "planCode", value: planCode))
    }
    if let token, !token.isEmpty, !items.contains(where: { $0.name == "token" }) {
      items.append(URLQueryItem(name: "token", value: token))
    }
    components.queryItems = items
    return components.url ?? self
  }
}
