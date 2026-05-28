import Foundation

struct OfficialFeedPageResult {
  let articles: [CachedArticle]
  let page: Int
  let totalPages: Int
  let hasMore: Bool
}

enum OfficialFeedPagination {
  /// 官网分页从 0 起算：第 1 页为栏目根路径，第 2 页为 `index_1.html`。
  static func pageURL(for category: OfficialCategory, page: Int) -> URL {
    let normalizedBase = category.url.absoluteString.hasSuffix("/")
      ? category.url.absoluteString
      : category.url.absoluteString + "/"
    if page <= 1 {
      return URL(string: normalizedBase)!
    }
    return URL(string: "\(normalizedBase)index_\(page - 1).html")!
  }

  static func totalPages(in html: String) -> Int {
    if let countPage = html.firstMatch(of: #"var\s+countPage\s*=\s*(\d+)"#)?[safe: 1],
       let value = Int(countPage)
    {
      return max(value, 1)
    }

    if let labeled = html.firstMatch(of: #"document\.write\("共"\+"(\d+)"\+"页"\)"#)?[safe: 1],
       let value = Int(labeled)
    {
      return max(value, 1)
    }

    if let labeled = html.firstMatch(of: #"共\s*(\d+)\s*页"#)?[safe: 1],
       let value = Int(labeled)
    {
      return max(value, 1)
    }

    let numberedPages = html
      .matches(of: #"index_(\d+)\.html"#)
      .compactMap { match -> Int? in
        guard let value = match[safe: 1] else { return nil }
        return Int(value)
      }

    if let maxIndex = numberedPages.max() {
      return max(maxIndex + 1, 1)
    }

    return 1
  }
}
