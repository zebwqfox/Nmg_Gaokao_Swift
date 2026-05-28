import CoreFoundation
import CryptoKit
import Foundation

struct OfficialContentClient {
  var session: URLSession = OfficialSiteTrust.makeSession()

  let categories: [OfficialCategory] = [
    OfficialCategory(id: "notice", title: "通知公告", kind: .notice, examType: nil, url: URL(string: "https://www.nm.zsks.cn/tzgg/")!),
    OfficialCategory(id: "latest-news", title: "最新要闻", kind: .news, examType: nil, url: URL(string: "https://www.nm.zsks.cn/zxyw/")!),
    OfficialCategory(id: "home", title: "首页最新", kind: .latest, examType: nil, url: URL(string: "https://www.nm.zsks.cn/")!),
    OfficialCategory(id: "gaokao-notice", title: "高考公告", kind: .notice, examType: "高考", url: URL(string: "https://www.nm.zsks.cn/kszs/ptgk/ggl/")!),
    OfficialCategory(id: "gaokao-policy", title: "高考政策", kind: .policy, examType: "高考", url: URL(string: "https://www.nm.zsks.cn/kszs/ptgk/zcfg/")!),
    OfficialCategory(id: "policies", title: "政策法规", kind: .policy, examType: nil, url: URL(string: "https://www.nm.zsks.cn/zszc1/")!),
    OfficialCategory(id: "services", title: "服务平台", kind: .service, examType: nil, url: URL(string: "https://www.nm.zsks.cn/fwpt/")!),
    OfficialCategory(id: "zsb", title: "专升本", kind: .notice, examType: "专升本", url: URL(string: "https://www.nm.zsks.cn/kszs/zsbks/")!),
    OfficialCategory(id: "xuekao", title: "学考", kind: .notice, examType: "学考", url: URL(string: "https://www.nm.zsks.cn/kszs/xk/")!),
    OfficialCategory(id: "gzdz-topic", title: "高职单招专题", kind: .topic, examType: "高职单招", url: URL(string: "https://www.nm.zsks.cn/ztzl/2026gzdz/")!),
    OfficialCategory(id: "xuekao-topic", title: "学考报名专题", kind: .topic, examType: "学考", url: URL(string: "https://www.nm.zsks.cn/ztzl/xkxkbmzl/")!)
  ]

  func fetchFeed(category: OfficialCategory, limit: Int = 30) async throws -> [CachedArticle] {
    let (html, resolvedURL) = try await fetchTextWithFallback(category.url)
    let resolvedCategory = OfficialCategory(
      id: category.id,
      title: category.title,
      kind: category.kind,
      examType: category.examType,
      url: resolvedURL
    )
    let articles = parseListPage(html: html, category: resolvedCategory, limit: limit)
    return rankIfNeeded(articles, categoryID: resolvedCategory.id)
  }

  func rankedFeed(category: OfficialCategory, limit: Int = 40) async throws -> [CachedArticle] {
    try await fetchFeed(category: category, limit: limit)
  }

  func fetchArticle(from listItem: CachedArticle) async throws -> CachedArticle {
    if listItem.originalURL.pathExtension.lowercased().isDocumentExtension {
      return listItem
    }
    let (html, _) = try await fetchTextWithFallback(listItem.originalURL)
    return parseDetailPage(html: html, fallback: listItem)
  }

  func searchOfficialSite(query: String) async throws -> [CachedArticle] {
    var components = URLComponents(string: "https://www.nm.zsks.cn/web/search/375")!
    components.queryItems = [URLQueryItem(name: "content", value: query)]
    let (html, resolvedURL) = try await fetchTextWithFallback(components.url!)
    let category = OfficialCategory(id: "search", title: "搜索", kind: .latest, examType: nil, url: resolvedURL)
    let articles = parseListPage(html: html, category: category, limit: 50)
    return rankIfNeeded(articles, categoryID: category.id)
  }

  private func rankIfNeeded(_ articles: [CachedArticle], categoryID: String) -> [CachedArticle] {
    guard ["notice", "latest-news"].contains(categoryID) else { return articles }
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
    let linkRegex = #"<a[^>]+href=["']([^"']+)["'][^>]*(?:title=["']([^"']*)["'])?[^>]*>(.*?)</a>"#
    let matches = html.matches(of: linkRegex)
    var items: [CachedArticle] = []
    var seen = Set<String>()

    for match in matches {
      guard let href = match[safe: 1],
            let url = URL(string: href, relativeTo: category.url)?.absoluteURL
      else { continue }

      let rawTitle = match[safe: 2]?.nilIfBlank ?? match[safe: 3] ?? ""
      let title = rawTitle.strippingHTML.normalizedWhitespace
      guard shouldKeepListLink(title: title, url: url), seen.insert(url.absoluteString).inserted else {
        continue
      }

      let date = nearbyDate(for: match.fullMatch, in: html)
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

  private func parseDetailPage(html: String, fallback: CachedArticle) -> CachedArticle {
    let title = html.firstMatch(of: #"<h1[^>]*>(.*?)</h1>"#)?[safe: 1]?.strippingHTML.normalizedWhitespace
      ?? html.firstMatch(of: #"<div[^>]+class=["'][^"']*(?:title|bt|article-title)[^"']*["'][^>]*>(.*?)</div>"#)?[safe: 1]?.strippingHTML.normalizedWhitespace
      ?? fallback.title
    let published = html.firstMatch(of: #"发布时间[:：]\s*([0-9]{4}-[0-9]{2}-[0-9]{2}(?:\s+[0-9]{2}:[0-9]{2})?)"#)?[safe: 1]
      .flatMap { DateFormatters.articleDateTimeOrDate($0) }
      ?? fallback.publishedAt
    let source = html.firstMatch(of: #"来源[:：]\s*([^<\n]+)"#)?[safe: 1]?.strippingHTML.normalizedWhitespace
    let attachments = parseAttachments(html: html, baseURL: fallback.originalURL)
    let bodyHTML = html.firstMatch(of: #"<div[^>]+class=["'][^"']*(?:content|article|TRS_Editor)[^"']*["'][^>]*>(.*?)</div>\s*(?:<div|</body)"#)?[safe: 1] ?? html
    let body = trimChrome(from: bodyHTML.htmlToPlainText, title: title)

    return CachedArticle(
      id: fallback.id,
      categoryID: fallback.categoryID,
      categoryTitle: fallback.categoryTitle,
      kind: fallback.kind,
      title: title,
      summary: String(body.prefix(160)),
      body: body,
      source: source ?? fallback.source,
      publishedAt: published,
      originalURL: fallback.originalURL,
      attachments: attachments,
      isFavorite: fallback.isFavorite
    )
  }

  private func parseAttachments(html: String, baseURL: URL) -> [ArticleAttachment] {
    html.matches(of: #"<a[^>]+href=["']([^"']+\.(?:pdf|doc|docx|xls|xlsx))["'][^>]*>(.*?)</a>"#)
      .compactMap { match in
        guard let href = match[safe: 1],
              let url = URL(string: href, relativeTo: baseURL)?.absoluteURL
        else { return nil }
        let title = (match[safe: 2] ?? url.lastPathComponent).strippingHTML.normalizedWhitespace
        return ArticleAttachment(title: title, url: url, fileType: url.pathExtension.lowercased())
      }
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

  private func shouldKeepListLink(title: String, url: URL) -> Bool {
    guard !title.isEmpty else { return false }
    let ignored = ["首页", "上一页", "下一页", "尾页", "更多>>", "政务服务", "网站地图"]
    if ignored.contains(title) { return false }
    if url.absoluteString.contains("javascript:") { return false }
    return url.host?.contains("nm.zsks.cn") == true
  }

  private func stableID(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private func trimChrome(from text: String, title: String) -> String {
    let normalized = text.normalizedWhitespace
    guard let titleRange = normalized.range(of: title) else { return normalized }
    let afterTitle = normalized[titleRange.upperBound...]
    if let footer = afterTitle.range(of: "政务服务 | 网站地图") {
      return String(afterTitle[..<footer.lowerBound]).normalizedWhitespace
    }
    return String(afterTitle).normalizedWhitespace
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
  var htmlToPlainText: String {
    replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
      .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
      .replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
      .strippingHTML
  }

  var strippingHTML: String {
    replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&#13;", with: "\n")
  }

  var normalizedWhitespace: String {
    replacingOccurrences(of: "[ \\t\\r\\f]+", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "\\n\\s*\\n+", with: "\n\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var nilIfBlank: String? {
    normalizedWhitespace.isEmpty ? nil : self
  }

  func matches(of pattern: String) -> [RegexMatch] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
      return []
    }
    let range = NSRange(startIndex..<endIndex, in: self)
    return regex.matches(in: self, range: range).map { result in
      var groups: [String?] = []
      for index in 0..<result.numberOfRanges {
        let nsRange = result.range(at: index)
        guard let range = Range(nsRange, in: self) else {
          groups.append(nil)
          continue
        }
        groups.append(String(self[range]))
      }
      return RegexMatch(groups: groups)
    }
  }

  func firstMatch(of pattern: String) -> RegexMatch? {
    matches(of: pattern).first
  }
}

private struct RegexMatch {
  let groups: [String?]

  var fullMatch: String { groups.first.flatMap { $0 } ?? "" }

  subscript(safe index: Int) -> String? {
    guard groups.indices.contains(index) else { return nil }
    return groups[index]
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
