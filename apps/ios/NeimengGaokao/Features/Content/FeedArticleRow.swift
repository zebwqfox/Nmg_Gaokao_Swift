import SwiftUI

struct FeedArticleRow: View {
  let article: CachedArticle
  let pinned: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top) {
        Text(article.title)
          .font(.headline)
          .foregroundStyle(.primary)
          .lineLimit(3)
        Spacer(minLength: 12)
        if pinned {
          Text("置顶")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.orange.gradient, in: Capsule())
        } else if !article.documentAttachments.isEmpty {
          Image(systemName: "paperclip")
            .foregroundStyle(.secondary)
        }
      }
      if pinned {
        let keywords = ImportantNewsRanker.matchedKeywords(in: article).prefix(3)
        if !keywords.isEmpty {
          Text(keywords.joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }
      if !article.summary.isEmpty, article.summary != article.title {
        Text(article.summary)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      HStack(spacing: 8) {
        Text(article.categoryTitle)
        if let publishedAt = article.publishedAt ?? OfficialArticleDateParser.date(from: article.originalURL) {
          Text(DateFormatters.displayDate.string(from: publishedAt))
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 6)
  }
}
