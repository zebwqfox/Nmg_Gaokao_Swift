import Foundation

struct OfficialFeedPageResult {
  let articles: [CachedArticle]
  let page: Int
  let totalPages: Int
  let hasMore: Bool
}

enum OfficialFeedPagination {
  static func pageURL(for category: OfficialCategory, page: Int) -> URL {
    let normalizedBase = category.url.absoluteString.hasSuffix("/")
      ? category.url.absoluteString
      : category.url.absoluteString + "/"
    if page <= 1 {
      return URL(string: normalizedBase)!
    }
    return URL(string: "\(normalizedBase)index_\(page).html")!
  }

  static func totalPages(in html: String) -> Int {
    let numberedPages = html
      .matches(of: #"index_(\d+)\.html"#)
      .compactMap { match -> Int? in
        guard let value = match[safe: 1] else { return nil }
        return Int(value)
      }
    return max(numberedPages.max() ?? 1, 1)
  }
}
