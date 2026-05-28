import Foundation

/// 官网站内搜索：`https://www.nm.zsks.cn/web/search/375?content=关键词`
enum OfficialSiteSearch {
  static let endpoint = URL(string: "https://www.nm.zsks.cn/web/search/375")!

  static func pageURL(query: String, page: Int) -> URL {
    var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
    var items = [URLQueryItem(name: "content", value: query)]
    if page > 1 {
      items.append(URLQueryItem(name: "page", value: String(page)))
    }
    components.queryItems = items
    return components.url ?? endpoint
  }

  static func totalPages(in html: String) -> Int {
    if let match = html.firstMatch(of: #"共\s*([0-9,]+)\s*页"#),
       let raw = match[safe: 1]?.replacingOccurrences(of: ",", with: ""),
       let pages = Int(raw)
    {
      return max(pages, 1)
    }
    return 1
  }

  static func cleanedTitle(_ title: String) -> String {
    title.replacingOccurrences(of: #"^【[^】]+】\s*"#, with: "", options: .regularExpression)
      .normalizedWhitespace
  }
}
