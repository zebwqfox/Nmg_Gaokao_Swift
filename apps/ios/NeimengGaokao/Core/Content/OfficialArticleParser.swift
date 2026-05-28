import Foundation

struct ParsedOfficialArticle {
  let title: String
  let source: String?
  let publishedAt: Date?
  let body: String
  let attachments: [ArticleAttachment]
}

enum OfficialArticleParser {
  static func parse(html: String, fallback: CachedArticle) -> ParsedOfficialArticle {
    let sanitized = stripScriptsAndStyles(from: html)
    let title = extractTitle(from: sanitized) ?? fallback.title
    let published = extractPublishedAt(from: sanitized) ?? fallback.publishedAt
    let source = extractSource(from: sanitized) ?? fallback.source
    let contentHTML = extractContentHTML(from: sanitized) ?? ""
    let images = parseImages(html: contentHTML.isEmpty ? sanitized : contentHTML, baseURL: fallback.originalURL)
    let documents = parseDocuments(html: sanitized, baseURL: fallback.originalURL)
    let body = plainText(from: contentHTML.isEmpty ? sanitized : contentHTML, title: title)

    return ParsedOfficialArticle(
      title: title,
      source: source,
      publishedAt: published,
      body: body,
      attachments: mergeAttachments(images: images, documents: documents)
    )
  }

  private static func stripScriptsAndStyles(from html: String) -> String {
    html
      .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: "", options: [.regularExpression, .caseInsensitive])
      .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: "", options: [.regularExpression, .caseInsensitive])
      .replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
  }

  private static func extractTitle(from html: String) -> String? {
    html.firstMatch(of: #"<h1[^>]*>([\s\S]*?)</h1>"#)?[safe: 1]?.strippingHTML.normalizedWhitespace.nilIfBlank
      ?? html.firstMatch(of: #"<div[^>]+class=["'][^"']*(?:title|bt|article-title)[^"']*["'][^>]*>([\s\S]*?)</div>"#)?[safe: 1]?
      .strippingHTML.normalizedWhitespace.nilIfBlank
  }

  private static func extractPublishedAt(from html: String) -> Date? {
    html.firstMatch(of: #"发布时间[:：]\s*([0-9]{4}-[0-9]{2}-[0-9]{2}(?:\s+[0-9]{2}:[0-9]{2})?)"#)?[safe: 1]
      .flatMap { DateFormatters.articleDateTimeOrDate($0) }
  }

  private static func extractSource(from html: String) -> String? {
    html.firstMatch(of: #"来源[:：]\s*([^<\n]+)"#)?[safe: 1]?.strippingHTML.normalizedWhitespace.nilIfBlank
  }

  private static func extractContentHTML(from html: String) -> String? {
    let classMarkers = ["TRS_Editor", "Custom_UnionStyle", "bt_content", "article-content", "xl-chrome"]
    for marker in classMarkers {
      if let block = extractDivBlock(containing: marker, in: html) {
        return block
      }
    }
    if let zoom = extractDivBlock(containing: "id=\"zoom\"", in: html) {
      return zoom
    }
    return extractBetweenMarkers(in: html)
  }

  private static func extractDivBlock(containing marker: String, in html: String) -> String? {
    guard let markerRange = html.range(of: marker, options: .caseInsensitive) else { return nil }
    guard let divStart = html[..<markerRange.lowerBound].range(of: "<div", options: [.caseInsensitive, .backwards])?
      .lowerBound
    else { return nil }
    return extractBalancedDiv(from: html, startingAt: divStart)
  }

  private static func extractBalancedDiv(from html: String, startingAt start: String.Index) -> String? {
    var index = start
    var depth = 0

    while index < html.endIndex {
      let remainder = html[index...]
      if remainder.lowercased().hasPrefix("<div") {
        depth += 1
        index = html.index(index, offsetBy: 4, limitedBy: html.endIndex) ?? html.endIndex
        continue
      }
      if remainder.lowercased().hasPrefix("</div>") {
        depth -= 1
        let end = html.index(index, offsetBy: 6, limitedBy: html.endIndex) ?? html.endIndex
        if depth == 0 {
          return String(html[start..<end])
        }
        index = end
        continue
      }
      index = html.index(after: index)
    }
    return nil
  }

  private static func extractBetweenMarkers(in html: String) -> String? {
    let startMarkers = ["</h1>", "来源：", "来源:"]
    let endMarkers = ["var xgwd", "document.write", "政务服务", "_hmt", "蒙ICP备", "<footer"]

    guard let start = startMarkers.compactMap({ html.range(of: $0)?.upperBound }).first else { return nil }
    let tail = html[start...]
    guard let end = endMarkers.compactMap({ tail.range(of: $0)?.lowerBound }).min() else {
      return String(tail)
    }
    return String(tail[..<end])
  }

  private static func parseImages(html: String, baseURL: URL) -> [ArticleAttachment] {
    html.matches(of: #"<img[^>]+src=["']([^"']+)["'][^>]*>"#)
      .compactMap { match -> ArticleAttachment? in
        guard let src = match[safe: 1],
              let url = URL(string: src, relativeTo: baseURL)?.absoluteURL
        else { return nil }
        let alt = match.fullMatch.firstMatch(of: #"alt=["']([^"']*)["']"#)?[safe: 1]?
          .strippingHTML.normalizedWhitespace
        let title = alt?.nilIfBlank ?? url.lastPathComponent
        return ArticleAttachment(title: title, url: url, fileType: "image")
      }
  }

  private static func parseDocuments(html: String, baseURL: URL) -> [ArticleAttachment] {
    html.matches(of: #"<a[^>]+href=["']([^"']+\.(?:pdf|doc|docx|xls|xlsx))["'][^>]*>([\s\S]*?)</a>"#)
      .compactMap { match in
        guard let href = match[safe: 1],
              let url = URL(string: href, relativeTo: baseURL)?.absoluteURL
        else { return nil }
        let title = (match[safe: 2] ?? url.lastPathComponent).strippingHTML.normalizedWhitespace
        return ArticleAttachment(title: title, url: url, fileType: url.pathExtension.lowercased())
      }
  }

  private static func mergeAttachments(images: [ArticleAttachment], documents: [ArticleAttachment]) -> [ArticleAttachment] {
    var seen = Set<String>()
    return (images + documents).filter { seen.insert($0.url.absoluteString).inserted }
  }

  private static func plainText(from html: String, title: String) -> String {
    var text = html
      .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
      .replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
      .replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
      .replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)
      .replacingOccurrences(of: "<img[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
      .strippingHTML
      .normalizedWhitespace

    let noise = [
      "发布时间", "来源：", "来源:", "var xgwd", "document.write",
      "function goPAGE", "$.ajax", "政务服务", "网站地图", "蒙ICP备", "蒙公网安备"
    ]
    if let earliest = noise.compactMap({ text.range(of: $0)?.lowerBound }).min(by: {
      text.distance(from: text.startIndex, to: $0) < text.distance(from: text.startIndex, to: $1)
    }) {
      text = String(text[..<earliest]).normalizedWhitespace
    }

    if let titleRange = text.range(of: title) {
      text = String(text[titleRange.upperBound...]).normalizedWhitespace
    }

    return text
  }
}

private extension String {
  var nilIfBlank: String? {
    normalizedWhitespace.isEmpty ? nil : self
  }
}
