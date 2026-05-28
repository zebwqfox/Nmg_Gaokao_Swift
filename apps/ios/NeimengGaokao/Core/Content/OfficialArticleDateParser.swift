import Foundation

enum OfficialArticleDateParser {
  static func date(from url: URL) -> Date? {
    let path = url.path
    if let match = path.firstMatch(of: #"t(20\d{2})(\d{2})(\d{2})"#),
       let date = makeDate(year: match[safe: 1], month: match[safe: 2], day: match[safe: 3])
    {
      return date
    }
    return nil
  }

  static func resolvedDate(listDate: Date?, url: URL) -> Date? {
    listDate ?? date(from: url)
  }

  static func sortDate(for article: CachedArticle) -> Date {
    article.publishedAt ?? date(from: article.originalURL) ?? article.cachedAt
  }

  private static func makeDate(year: String?, month: String?, day: String?) -> Date? {
    guard let year, let month, let day,
          let yearValue = Int(year),
          let monthValue = Int(month),
          let dayValue = Int(day)
    else {
      return nil
    }

    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.year = yearValue
    components.month = monthValue
    components.day = dayValue
    return components.date
  }
}
