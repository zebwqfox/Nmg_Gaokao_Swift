import CoreFoundation
import CryptoKit
import Foundation

struct OfficialContentClient {
  var session: URLSession = OfficialSiteTrust.makeSession()

  /// 资讯页仅抓取官网「通知公告」「最新要闻」两个栏目。
  let categories: [OfficialCategory] = [
    OfficialCategory(id: "notice", title: "通知公告", kind: .notice, examType: nil, url: URL(string: "https://www.nm.zsks.cn/tzgg/")!),
    OfficialCategory(id: "latest-news", title: "最新要闻", kind: .news, examType: nil, url: URL(string: "https://www.nm.zsks.cn/zxyw/")!)
  ]

  func fetchFeedPage(category: OfficialCategory, page: Int, perPageLimit: Int = 30) async throws -> OfficialFeedPageResult {
    let pageURL = OfficialFeedPagination.pageURL(for: category, page: page)
    let (html, resolvedURL) = try await fetchTextWithFallback(pageURL)
    let resolvedCategory = OfficialCategory(
      id: category.id,
      title: category.title,
      kind: category.kind,
      examType: category.examType,
      url: resolvedURL
    )
    let totalPages = OfficialFeedPagination.totalPages(in: html)
    let articles = rankIfNeeded(
      parseListPage(html: html, category: resolvedCategory, limit: perPageLimit),
      categoryID: resolvedCategory.id
    )
    return OfficialFeedPageResult(
      articles: articles,
      page: page,
      totalPages: totalPages,
      hasMore: page < totalPages && !articles.isEmpty
    )
  }

  func fetchFeed(category: OfficialCategory, limit: Int = 30) async throws -> [CachedArticle] {
    try await fetchFeedPage(category: category, page: 1, perPageLimit: limit).articles
  }

  func rankedFeed(category: OfficialCategory, limit: Int = 40) async throws -> [CachedArticle] {
    try await fetchFeed(category: category, limit: limit)
  }

  func fetchArticle(from listItem: CachedArticle) async throws -> CachedArticle {
    if listItem.originalURL.pathExtension.lowercased().isDocumentExtension {
      return listItem
    }
    let (html, _) = try await fetchTextWithFallback(listItem.originalURL)
    let fallback = listItem
    return await Task.detached(priority: .userInitiated) {
      Self.parseDetailPage(html: html, fallback: fallback)
    }.value
  }

  func searchOfficialSite(query: String) async throws -> [CachedArticle] {
    try await searchOfficialSitePage(query: query, page: 1).articles
  }

  func searchOfficialSitePage(query: String, page: Int, perPageLimit: Int = 20) async throws -> OfficialFeedPageResult {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return OfficialFeedPageResult(articles: [], page: 1, totalPages: 1, hasMore: false)
    }

    let pageURL = OfficialSiteSearch.pageURL(query: trimmed, page: page)
    let (html, resolvedURL) = try await fetchTextWithFallback(pageURL)
    let category = OfficialCategory(id: "search", title: "搜索", kind: .latest, examType: nil, url: resolvedURL)
    let totalPages = OfficialSiteSearch.totalPages(in: html)
    let articles = rankIfNeeded(
      parseSearchResults(html: html, category: category, limit: perPageLimit),
      categoryID: category.id
    )
    return OfficialFeedPageResult(
      articles: articles,
      page: page,
      totalPages: totalPages,
      hasMore: page < totalPages && !articles.isEmpty
    )
  }

  private func parseSearchResults(html: String, category: OfficialCategory, limit: Int) -> [CachedArticle] {
    parseListPage(html: html, category: category, limit: limit).map { article in
      CachedArticle(
        id: article.id,
        categoryID: article.categoryID,
        categoryTitle: article.categoryTitle,
        kind: article.kind,
        title: OfficialSiteSearch.cleanedTitle(article.title),
        summary: OfficialSiteSearch.cleanedTitle(article.summary),
        body: article.body,
        source: article.source,
        publishedAt: article.publishedAt,
        originalURL: article.originalURL,
        attachments: article.attachments,
        isFavorite: article.isFavorite,
        cachedAt: article.cachedAt
      )
    }
  }

  private func rankIfNeeded(_ articles: [CachedArticle], categoryID: String) -> [CachedArticle] {
    guard ["notice", "latest-news", "search"].contains(categoryID) else { return articles }
    return ImportantNewsRanker.ranked(articles)
  }

  private func fetchTextWithFallback(_ url: URL) async throws -> (text: String, resolvedURL: URL) {
    let candidates = candidateURLs(for: url)
    var lastError: Error?

    for candidate in candidates {
      do {
        let text = try await fetchText(candidate)
        return (text, candidate)
      } catch {
        lastError = error
      }
    }

    throw lastError ?? URLError(.cannotLoadFromNetwork)
  }

  private func fetchText(_ url: URL) async throws -> String {
    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 25
    request.setValue("NeimengGaokaoApp/0.1", forHTTPHeaderField: "User-Agent")
    request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw URLError(.badServerResponse)
    }
    return String(data: data, encoding: .utf8)
      ?? String(data: data, encoding: .gb18030)
      ?? ""
  }

  private func candidateURLs(for url: URL) -> [URL] {
    guard let scheme = url.scheme?.lowercased(),
          let host = url.host?.lowercased(),
          host.contains("nm.zsks.cn")
    else {
      return [url]
    }

    if scheme == "https", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
      components.scheme = "http"
      if let fallback = components.url {
        return [url, fallback]
      }
    } else if scheme == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
      components.scheme = "https"
      if let fallback = components.url {
        return [url, fallback]
      }
    }

    return [url]
  }

  private func parseListPage(
    html: String,
    category: OfficialCategory,
    limit: Int
  ) -> [CachedArticle] {
    let scopedHTML = OfficialArticleListFilter.listContentHTML(from: html)
    let linkRegex = #"<a[^>]+href=["']([^"']+)["'][^>]*(?:title=["']([^"']*)["'])?[^>]*>(.*?)</a>"#
    let matches = scopedHTML.matches(of: linkRegex)
    var items: [CachedArticle] = []
    var seen = Set<String>()

    for match in matches {
      guard let href = match[safe: 1],
            let url = URL(string: href, relativeTo: category.url)?.absoluteURL
      else { continue }

      let rawTitle = match[safe: 2]?.nilIfBlank ?? match[safe: 3] ?? ""
      let title = rawTitle.strippingHTML.normalizedWhitespace
      let date = nearbyDate(for: match.fullMatch, in: scopedHTML)
      guard OfficialArticleListFilter.shouldKeepListLink(title: title, url: url, hasNearbyDate: date != nil),
            seen.insert(url.absoluteString).inserted
      else {
        continue
      }
      items.append(CachedArticle(
        id: stableID(url.absoluteString),
        categoryID: category.id,
        categoryTitle: category.title,
        kind: category.kind,
        title: title,
        summary: title,
        body: "",
        source: nil,
        publishedAt: date,
        originalURL: url,
        attachments: url.pathExtension.lowercased().isDocumentExtension
          ? [ArticleAttachment(title: title, url: url, fileType: url.pathExtension.lowercased())]
          : []
      ))
      if items.count >= limit {
        break
      }
    }
    return items
  }

  private static func parseDetailPage(html: String, fallback: CachedArticle) -> CachedArticle {
    let parsed = OfficialArticleParser.parse(html: html, fallback: fallback)

    return CachedArticle(
      id: fallback.id,
      categoryID: fallback.categoryID,
      categoryTitle: fallback.categoryTitle,
      kind: fallback.kind,
      title: parsed.title,
      summary: String(parsed.body.prefix(160)),
      body: parsed.body,
      source: parsed.source ?? fallback.source,
      publishedAt: parsed.publishedAt,
      originalURL: fallback.originalURL,
      attachments: parsed.attachments,
      contentBlocks: parsed.contentBlocks,
      isFavorite: fallback.isFavorite
    )
  }

  private func nearbyDate(for match: String, in html: String) -> Date? {
    guard let range = html.range(of: match) else { return nil }
    let suffix = html[range.upperBound..<html.endIndex].prefix(160)
    if let date = String(suffix).firstMatch(of: #"([0-9]{4}-[0-9]{2}-[0-9]{2})"#)?[safe: 1] {
      return DateFormatters.articleDate.date(from: date)
    }
    if let shortDate = String(suffix).firstMatch(of: #"([0-9]{2}-[0-9]{2})"#)?[safe: 1] {
      return DateFormatters.monthDay.date(from: "2026-\(shortDate)")
    }
    return nil
  }

  private func stableID(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }

}

enum DateFormatters {
  static let articleDate: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  static let articleDateTime: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter
  }()

  static let displayDate: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "yyyy年M月d日"
    return formatter
  }()

  static let monthDay: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  static func articleDateTimeOrDate(_ value: String) -> Date? {
    articleDateTime.date(from: value) ?? articleDate.date(from: value)
  }
}

private extension String {
  var nilIfBlank: String? {
    normalizedWhitespace.isEmpty ? nil : self
  }
}

private extension String {
  var isDocumentExtension: Bool {
    ["pdf", "doc", "docx", "xls", "xlsx"].contains(lowercased())
  }
}

private extension String.Encoding {
  static let gb18030 = String.Encoding(
    rawValue: CFStringConvertEncodingToNSStringEncoding(
      CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
    )
  )
}
