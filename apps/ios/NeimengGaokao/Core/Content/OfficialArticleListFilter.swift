import Foundation

enum OfficialArticleListFilter {
  static let navigationTitles: Set<String> = [
    "首页", "考试招生", "政务公开", "联系我们", "双公示",
    "普通高考", "同等学力全国统考", "研究生考试", "全国计算机等级考试",
    "大学英语四六级考试", "自学考试", "初中学业水平考试(中考)", "成人高考",
    "高中学业水平考试", "教师资格考试", "特岗教师招考", "普通高等教育专升本",
    "预决算公开", "考试院概况", "信息公开规定", "信息公开指南", "信息公开目录",
    "智能客服", "更多>>", "上一页", "下一页", "尾页", "政务服务", "网站地图", "GO"
  ]

  static func listContentHTML(from html: String) -> String {
    let startMarkers = [
      "class=\"list_right",
      "class='list_right",
      "class=\"right_box",
      "class=\"ny_right",
      "class=\"mainR",
      "class=\"list_box",
      "id=\"list\"",
      "class=\"list\""
    ]

    for marker in startMarkers {
      guard let range = html.range(of: marker, options: .caseInsensitive) else { continue }
      let tail = html[range.lowerBound...]
      if let footer = tail.range(of: "政务服务", options: .caseInsensitive) {
        return String(tail[..<footer.lowerBound])
      }
      return String(tail)
    }

    if let leftEnd = html.range(of: "class=\"left", options: .caseInsensitive)
      ?? html.range(of: "class=\"subnav", options: .caseInsensitive)
    {
      let tail = html[leftEnd.upperBound...]
      if let rightStart = tail.range(of: "class=\"right", options: .caseInsensitive)
        ?? tail.range(of: "class=\"list_right", options: .caseInsensitive)
      {
        let content = tail[rightStart.lowerBound...]
        if let footer = content.range(of: "政务服务", options: .caseInsensitive) {
          return String(content[..<footer.lowerBound])
        }
        return String(content)
      }
    }

    return html
  }

  static func shouldKeepListLink(title: String, url: URL, hasNearbyDate: Bool) -> Bool {
    let normalizedTitle = title.normalizedWhitespace
    guard !normalizedTitle.isEmpty else { return false }
    if navigationTitles.contains(normalizedTitle) { return false }
    if url.absoluteString.contains("javascript:") { return false }
    guard url.host?.contains("nm.zsks.cn") == true else { return false }

    if isArticleURL(url) { return true }
    if hasNearbyDate { return true }

    if isCategoryIndexURL(url) { return false }
    if normalizedTitle.count < 12 { return false }
    return normalizedTitle.contains("20") || normalizedTitle.contains("公告") || normalizedTitle.contains("通知")
  }

  static func isArticleURL(_ url: URL) -> Bool {
    let path = url.path
    if path.range(of: #"/20\d{4}/t\d"#, options: .regularExpression) != nil { return true }
    if path.range(of: #"/t20\d{6}_\d+\.html"#, options: .regularExpression) != nil { return true }
    if path.hasSuffix(".html"), path.split(separator: "/").count >= 4 { return true }
    if DocumentAttachmentExtensions.isDocument(url: url) { return true }
    return false
  }

  private static func isCategoryIndexURL(_ url: URL) -> Bool {
    let path = url.path
    if path.hasSuffix("/") { return true }
    let segments = path.split(separator: "/").map(String.init)
    guard segments.count <= 3 else { return false }
    return !path.contains(".html")
  }
}
