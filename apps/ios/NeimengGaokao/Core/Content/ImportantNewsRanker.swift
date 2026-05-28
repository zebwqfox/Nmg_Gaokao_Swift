import Foundation

/// 通知公告 / 最新要闻的重要词词库与置顶排序。
enum ImportantNewsRanker {
  static let minimumPinScore = 35

  static let keywordWeights: [(keyword: String, weight: Int)] = [
    ("高考", 120),
    ("普通高考", 115),
    ("平安高考", 110),
    ("报名", 95),
    ("志愿填报", 100),
    ("志愿", 90),
    ("填报", 85),
    ("录取", 90),
    ("投档", 85),
    ("分数线", 80),
    ("成绩", 75),
    ("准考证", 95),
    ("打印", 60),
    ("体检", 70),
    ("复查", 65),
    ("禁带", 80),
    ("专升本", 70),
    ("体育统考", 70),
    ("艺考", 65),
    ("统考", 60),
    ("缴费", 65),
    ("政策", 55),
    ("公告", 45),
    ("实施方案", 50),
    ("温馨提示", 40),
    ("重要提醒", 100),
    ("暖心护航", 75)
  ]

  static func score(_ article: CachedArticle) -> Int {
    let text = "\(article.title) \(article.summary) \(article.body)"
    var total = 0
    var matched = Set<String>()

    for entry in keywordWeights where text.localizedCaseInsensitiveContains(entry.keyword) {
      guard matched.insert(entry.keyword).inserted else { continue }
      total += entry.weight
    }

    if article.categoryID == "notice" || article.categoryID == "latest-news" {
      total += 5
    }
    return total
  }

  static func isPinned(_ article: CachedArticle) -> Bool {
    score(article) >= minimumPinScore
  }

  static func ranked(_ articles: [CachedArticle]) -> [CachedArticle] {
    articles.sorted { lhs, rhs in
      let leftScore = score(lhs)
      let rightScore = score(rhs)
      if leftScore != rightScore {
        return leftScore > rightScore
      }
      let leftDate = lhs.publishedAt ?? lhs.cachedAt
      let rightDate = rhs.publishedAt ?? rhs.cachedAt
      return leftDate > rightDate
    }
  }

  static func pinned(_ articles: [CachedArticle]) -> [CachedArticle] {
    ranked(articles).filter(isPinned)
  }

  static func regular(from articles: [CachedArticle]) -> [CachedArticle] {
    let pinnedIDs = Set(pinned(articles).map(\.id))
    return ranked(articles).filter { !pinnedIDs.contains($0.id) }
  }

  static func matchedKeywords(in article: CachedArticle) -> [String] {
    let text = "\(article.title) \(article.summary)"
    return keywordWeights
      .map(\.keyword)
      .filter { text.localizedCaseInsensitiveContains($0) }
  }
}
