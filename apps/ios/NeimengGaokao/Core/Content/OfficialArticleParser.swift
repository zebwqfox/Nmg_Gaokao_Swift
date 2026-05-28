import Foundation

struct ParsedOfficialArticle {
  let title: String
  let source: String?
  let publishedAt: Date?
  let body: String
  let contentBlocks: [ArticleContentBlock]
  let attachments: [ArticleAttachment]
}

enum OfficialArticleParser {
  private static let maxContentBlockLength = 300_000

  static func parse(html: String, fallback: CachedArticle) -> ParsedOfficialArticle {
    let documents = mergeAttachments(
      parseAllAttachments(html: html, baseURL: fallback.originalURL),
      fallback.attachments
    )
    let sanitized = stripScriptsAndStyles(from: html)
    let title = extractTitle(from: sanitized) ?? fallback.title
    let published = extractPublishedAt(from: sanitized) ?? fallback.publishedAt
    let source = extractSource(from: sanitized) ?? fallback.source
    let contentHTML = extractContentHTML(from: sanitized) ?? ""
    let sourceHTML = contentHTML.isEmpty ? sanitized : contentHTML
    let contentBlocks = parseContentBlocks(html: sourceHTML, baseURL: fallback.originalURL)
    let body = plainText(from: sourceHTML, title: title)

    return ParsedOfficialArticle(
      title: title,
      source: source,
      publishedAt: published,
      body: body,
      contentBlocks: contentBlocks,
      attachments: documents
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
      if html.distance(from: start, to: index) > maxContentBlockLength {
        return nil
      }

      let remainder = html[index...]
      let openRange = remainder.range(of: "<div", options: .caseInsensitive)
      let closeRange = remainder.range(of: "</div>", options: .caseInsensitive)

      let useOpen: Bool
      switch (openRange, closeRange) {
      case let (open?, close?):
        useOpen = open.lowerBound <= close.lowerBound
      case (.some, .none):
        useOpen = true
      case (.none, .some):
        useOpen = false
      case (.none, .none):
        return nil
      }

      if useOpen, let openRange {
        depth += 1
        index = openRange.upperBound
      } else if let closeRange {
        depth -= 1
        index = closeRange.upperBound
        if depth == 0 {
          let block = String(html[start..<index])
          return block.count <= maxContentBlockLength ? block : nil
        }
      }
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

  private static func parseContentBlocks(html: String, baseURL: URL) -> [ArticleContentBlock] {
    var blocks: [ArticleContentBlock] = []
    var cursor = html.startIndex

    while cursor < html.endIndex {
      let remainder = html[cursor...]
      let imgStart = remainder.range(of: "<img", options: .caseInsensitive)?.lowerBound
      let tableStart = remainder.range(of: "<table", options: .caseInsensitive)?.lowerBound

      enum BlockKind {
        case image(String.Index)
        case table(String.Index)
      }

      let next: BlockKind?
      switch (imgStart, tableStart) {
      case let (image?, table?):
        next = image < table ? .image(image) : .table(table)
      case let (image?, nil):
        next = .image(image)
      case let (nil, table?):
        next = .table(table)
      case (nil, nil):
        next = nil
      }

      guard let next else {
        appendTextBlock(from: remainder, to: &blocks)
        break
      }

      switch next {
      case .image(let start):
        appendTextBlock(from: html[cursor..<start], to: &blocks)
        guard let tagEnd = html.range(of: ">", range: start..<html.endIndex)?.upperBound else {
          cursor = html.endIndex
          break
        }

        let tagHTML = String(html[start..<tagEnd])
        if let src = extractImageSrc(from: tagHTML) {
          let alt = tagHTML.firstMatch(of: #"alt=["']([^"']*)["']"#)?[safe: 1]?
            .strippingHTML.normalizedWhitespace
          appendImageBlock(src: src, alt: alt, baseURL: baseURL, to: &blocks)
        }
        cursor = tagEnd

      case .table(let start):
        appendTextBlock(from: html[cursor..<start], to: &blocks)
        if let table = parseTable(from: html, startingAt: start) {
          blocks.append(.table(rows: table.rows))
          cursor = table.endIndex
        } else {
          cursor = html.index(after: start)
        }
      }
    }

    return blocks.isEmpty ? fallbackTextBlocks(from: html, title: "", baseURL: baseURL) : blocks
  }

  private static func parseTable(from html: String, startingAt start: String.Index) -> (rows: [[String]], endIndex: String.Index)? {
    guard let endIndex = extractBalancedTag("table", from: html, startingAt: start) else { return nil }
    let tableHTML = String(html[start..<endIndex])
    let rows = buildTableGrid(from: tableHTML)
    guard !rows.isEmpty else { return nil }
    return (rows, endIndex)
  }

  private struct ParsedTableCell {
    let text: String
    let colspan: Int
    let rowspan: Int
  }

  private static func buildTableGrid(from tableHTML: String) -> [[String]] {
    var grid: [[String]] = []
    var rowspanCarry: [Int: Int] = [:]

    let rowHTMLs = tableHTML
      .matches(of: #"<tr[^>]*>([\s\S]*?)</tr>"#)
      .map { $0[safe: 1] ?? "" }

    for rowHTML in rowHTMLs {
      var row: [String] = []
      var col = 0
      let cells = parseTableCells(from: rowHTML)
      var cellIndex = 0

      while cellIndex < cells.count {
        while let rowsLeft = rowspanCarry[col], rowsLeft > 0 {
          row.append("")
          if rowsLeft > 1 {
            rowspanCarry[col] = rowsLeft - 1
          } else {
            rowspanCarry.removeValue(forKey: col)
          }
          col += 1
        }

        let cell = cells[cellIndex]
        cellIndex += 1

        for spanIndex in 0..<cell.colspan {
          row.append(spanIndex == 0 ? cell.text : "")
          if cell.rowspan > 1 {
            rowspanCarry[col + spanIndex] = cell.rowspan - 1
          }
        }
        col += cell.colspan
      }

      while let rowsLeft = rowspanCarry[col], rowsLeft > 0 {
        row.append("")
        if rowsLeft > 1 {
          rowspanCarry[col] = rowsLeft - 1
        } else {
          rowspanCarry.removeValue(forKey: col)
        }
        col += 1
      }

      if !row.isEmpty {
        grid.append(row)
      }
    }

    let width = grid.map(\.count).max() ?? 0
    return grid.map { row in
      row + Array(repeating: "", count: max(0, width - row.count))
    }
  }

  private static func parseTableCells(from rowHTML: String) -> [ParsedTableCell] {
    rowHTML
      .matches(of: #"<t([dh])([^>]*)>([\s\S]*?)</t\1>"#)
      .map { match in
        let attributes = match[safe: 2] ?? ""
        let content = match[safe: 3] ?? ""
        return ParsedTableCell(
          text: plainTextFragment(from: content),
          colspan: htmlAttributeInt(named: "colspan", in: attributes),
          rowspan: htmlAttributeInt(named: "rowspan", in: attributes)
        )
      }
  }

  private static func htmlAttributeInt(named name: String, in attributes: String) -> Int {
    let pattern = "\(name)\\s*=\\s*[\"']?(\\d+)[\"']?"
    guard let value = attributes.firstMatch(of: pattern)?[safe: 1],
          let int = Int(value)
    else {
      return 1
    }
    return max(int, 1)
  }

  private static func extractBalancedTag(_ tag: String, from html: String, startingAt start: String.Index) -> String.Index? {
    var index = start
    var depth = 0
    let openToken = "<\(tag)"
    let closeToken = "</\(tag)>"

    while index < html.endIndex {
      let remainder = html[index...]
      let openRange = remainder.range(of: openToken, options: .caseInsensitive)
      let closeRange = remainder.range(of: closeToken, options: .caseInsensitive)

      let useOpen: Bool
      switch (openRange, closeRange) {
      case let (open?, close?):
        useOpen = open.lowerBound <= close.lowerBound
      case (.some, .none):
        useOpen = true
      case (.none, .some):
        useOpen = false
      case (.none, .none):
        return nil
      }

      if useOpen, let openRange {
        depth += 1
        index = openRange.upperBound
      } else if let closeRange {
        depth -= 1
        index = closeRange.upperBound
        if depth == 0 {
          return index
        }
      }
    }
    return nil
  }

  private static func extractImageSrc(from tagHTML: String) -> String? {
    let attributePattern = #"(?:src|data-src|fileurl|data-original|original)\s*=\s*["']([^"']+)["']"#
    if let quoted = tagHTML.firstMatch(of: attributePattern)?[safe: 1] {
      return quoted
    }
    let unquotedPattern = #"(?:src|data-src|fileurl|data-original|original)\s*=\s*([^\s>]+)"#
    return tagHTML.firstMatch(of: unquotedPattern)?[safe: 1]
  }

  private static func appendImageBlock(
    src: String,
    alt: String?,
    baseURL: URL,
    to blocks: inout [ArticleContentBlock]
  ) {
    let trimmed = src.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    let caption = alt?.nilIfBlank ?? "正文插图"
    let lowercased = trimmed.lowercased()

    if lowercased.hasPrefix("data:") {
      blocks.append(.inlineImagePayload(trimmed, caption: caption))
      return
    }

    if let url = resolveImageURL(trimmed, baseURL: baseURL) {
      let remoteCaption = alt?.nilIfBlank ?? url.lastPathComponent
      blocks.append(.remoteImage(url: url, caption: remoteCaption))
    }
  }

  private static func appendTextBlock(from html: Substring, to blocks: inout [ArticleContentBlock]) {
    let text = plainTextFragment(from: String(html))
    guard !text.isEmpty else { return }
    if case .text(let existing)? = blocks.last {
      blocks[blocks.count - 1] = .text(existing + "\n\n" + text)
    } else {
      blocks.append(.text(text))
    }
  }

  private static func plainTextFragment(from html: String) -> String {
    html
      .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
      .replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
      .replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
      .replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)
      .strippingHTML
      .normalizedWhitespace
  }

  private static func fallbackTextBlocks(from html: String, title: String, baseURL: URL) -> [ArticleContentBlock] {
    let text = plainText(from: html, title: title)
    return text.isEmpty ? [] : [.text(text)]
  }

  private static func resolveImageURL(_ src: String, baseURL: URL) -> URL? {
    let trimmed = src.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.lowercased().hasPrefix("data:") {
      return nil
    }
    if trimmed.hasPrefix("//") {
      return URL(string: "https:\(trimmed)")
    }
    return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
  }

  private static func parseDocuments(html: String, baseURL: URL) -> [ArticleAttachment] {
    html.matches(of: #"<a[^>]+href=["']([^"']+)["'][^>]*>([\s\S]*?)</a>"#)
      .compactMap { match in
        guard let href = match[safe: 1],
              let url = URL(string: href, relativeTo: baseURL)?.absoluteURL,
              isDocumentURL(url)
        else { return nil }
        let title = (match[safe: 2] ?? url.lastPathComponent).strippingHTML.normalizedWhitespace
        return ArticleAttachment(
          title: title.nilIfBlank ?? url.lastPathComponent,
          url: url,
          fileType: DocumentAttachmentExtensions.fileExtension(from: url) ?? url.pathExtension.lowercased()
        )
      }
  }

  private static func parseAllAttachments(html: String, baseURL: URL) -> [ArticleAttachment] {
    var attachments = parseDocuments(html: html, baseURL: baseURL)
    attachments += parseScriptAttachments(html: html, baseURL: baseURL)

    if let sidebar = extractDivBlock(containing: "xianggwd", in: html) {
      attachments += parseDocuments(html: sidebar, baseURL: baseURL)
    }

    return mergeAttachments(attachments, [])
  }

  private static func parseScriptAttachments(html: String, baseURL: URL) -> [ArticleAttachment] {
    var attachments: [ArticleAttachment] = []

    if let xgwd = extractScriptStringVariable(named: "xgwd", from: html), !xgwd.isEmpty {
      attachments += attachmentsFromScriptPayload(xgwd, separator: ",", baseURL: baseURL)
    }
    if let str = extractScriptStringVariable(named: "str", from: html), !str.isEmpty {
      attachments += attachmentsFromScriptPayload(str, separator: "|", baseURL: baseURL)
    }

    return attachments
  }

  private static func extractScriptStringVariable(named name: String, from html: String) -> String? {
    guard let marker = html.range(of: "var \(name)", options: .caseInsensitive) else { return nil }
    guard let equals = html.range(of: "=", range: marker.upperBound..<html.endIndex)?.upperBound else { return nil }

    var index = equals
    while index < html.endIndex, html[index].isWhitespace {
      index = html.index(after: index)
    }
    guard index < html.endIndex else { return nil }

    let quote = html[index]
    guard quote == "'" || quote == "\"" else { return nil }
    index = html.index(after: index)

    var value = ""
    while index < html.endIndex {
      let character = html[index]
      if character == quote {
        return value
      }
      if character == "\\", html.index(after: index) < html.endIndex {
        index = html.index(after: index)
        value.append(html[index])
      } else {
        value.append(character)
      }
      index = html.index(after: index)
    }
    return value.isEmpty ? nil : value
  }

  private static func attachmentsFromScriptPayload(
    _ payload: String,
    separator: String,
    baseURL: URL
  ) -> [ArticleAttachment] {
    payload
      .split(separator: Character(separator), omittingEmptySubsequences: true)
      .flatMap { fragment -> [ArticleAttachment] in
        let piece = String(fragment).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !piece.isEmpty else { return [] }

        let linked = parseDocuments(html: piece, baseURL: baseURL)
        if !linked.isEmpty {
          return linked
        }

        let text = piece.strippingHTML.normalizedWhitespace
        guard !text.isEmpty else { return [] }

        if let url = URL(string: text, relativeTo: baseURL)?.absoluteURL, isDocumentURL(url) {
          let fileType = DocumentAttachmentExtensions.fileExtension(from: url) ?? url.pathExtension.lowercased()
          return [ArticleAttachment(title: text, url: url, fileType: fileType)]
        }

        return []
      }
  }

  private static func isDocumentURL(_ url: URL) -> Bool {
    DocumentAttachmentExtensions.isDocument(url: url)
  }

  private static func mergeAttachments(_ primary: [ArticleAttachment], _ secondary: [ArticleAttachment]) -> [ArticleAttachment] {
    var seen = Set<String>()
    return (primary + secondary).filter { attachment in
      seen.insert(attachment.url.absoluteString + attachment.title).inserted
    }
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
