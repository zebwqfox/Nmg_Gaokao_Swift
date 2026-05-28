import SwiftUI

struct CalendarView: View {
  @Environment(RouterPath.self) private var router

  private var events: [PolicyEvent] {
    ArticleSessionCache.allArticles
      .compactMap(PolicyEvent.init(article:))
      .sorted { $0.date > $1.date }
  }

  var body: some View {
    List {
      if events.isEmpty {
        ContentUnavailableView("暂无时间节点", systemImage: "calendar.badge.exclamationmark", description: Text("浏览资讯后，App 会从公告标题里整理报名、缴费、打印、查询等关键日期。"))
      } else {
        Section("从公告中整理") {
          ForEach(events) { event in
            Button {
              if let article = ArticleSessionCache.get(event.articleID) {
                ArticleSessionCache.store(article)
              }
              router.navigate(to: .article(id: event.articleID))
            } label: {
              HStack(spacing: 12) {
                VStack(spacing: 2) {
                  Text(event.month)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                  Text(event.day)
                    .font(.title3.weight(.bold))
                }
                .frame(width: 48, height: 54)
                .nativeGlassPanel(cornerRadius: 14, tint: .blue.opacity(0.08))

                VStack(alignment: .leading, spacing: 5) {
                  Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                  Text(event.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
              .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .navigationTitle("日历")
  }
}

private struct PolicyEvent: Identifiable {
  let id: String
  let articleID: String
  let date: Date
  let title: String
  let reason: String

  init?(article: CachedArticle) {
    let searchable = "\(article.title) \(article.summary) \(article.body)"
    let keywords = ["报名", "缴费", "准考证", "打印", "志愿", "成绩", "录取", "考试", "审核"]
    guard keywords.contains(where: searchable.contains) else { return nil }

    let date = PolicyEvent.extractDate(from: searchable) ?? article.publishedAt
    guard let date else { return nil }

    self.id = "\(article.id)-\(date.timeIntervalSince1970)"
    self.articleID = article.id
    self.date = date
    self.title = article.title
    self.reason = article.categoryTitle
  }

  var month: String {
    let month = Foundation.Calendar.current.component(.month, from: date)
    return "\(month)月"
  }

  var day: String {
    let day = Foundation.Calendar.current.component(.day, from: date)
    return "\(day)"
  }

  private static func extractDate(from text: String) -> Date? {
    let patterns = [
      #"([0-9]{4})年([0-9]{1,2})月([0-9]{1,2})日"#,
      #"([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})"#
    ]
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
            match.numberOfRanges == 4,
            let yearRange = Range(match.range(at: 1), in: text),
            let monthRange = Range(match.range(at: 2), in: text),
            let dayRange = Range(match.range(at: 3), in: text)
      else { continue }

      var components = DateComponents()
      components.calendar = Foundation.Calendar(identifier: .gregorian)
      components.year = Int(text[yearRange])
      components.month = Int(text[monthRange])
      components.day = Int(text[dayRange])
      return components.date
    }
    return nil
  }
}
