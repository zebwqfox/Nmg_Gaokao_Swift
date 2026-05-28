import SwiftData
import SwiftUI

struct ContentFeedView: View {
  @Environment(RouterPath.self) private var router
  @Environment(\.contentClient) private var contentClient
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \CachedArticle.cachedAt, order: .reverse) private var cachedArticles: [CachedArticle]

  @State private var selectedCategoryID = "notice"
  @State private var query = ""
  @State private var loadState: LoadState<[CachedArticle]> = .idle

  private var selectedCategory: OfficialCategory {
    contentClient.categories.first(where: { $0.id == selectedCategoryID }) ?? contentClient.categories[0]
  }

  private var displayedArticles: [CachedArticle] {
    switch loadState {
    case .loaded(let articles):
      return articles
    default:
      let local = cachedArticles.filter { $0.categoryID == selectedCategoryID }
      if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return ImportantNewsRanker.ranked(local)
      }
      return ImportantNewsRanker.ranked(
        local.filter { article in
          article.title.localizedCaseInsensitiveContains(query)
            || article.summary.localizedCaseInsensitiveContains(query)
            || article.body.localizedCaseInsensitiveContains(query)
        }
      )
    }
  }

  private var pinnedArticles: [CachedArticle] {
    guard usesImportantRanking else { return [] }
    return ImportantNewsRanker.pinned(displayedArticles)
  }

  private var regularArticles: [CachedArticle] {
    guard usesImportantRanking else { return displayedArticles }
    return ImportantNewsRanker.regular(from: displayedArticles)
  }

  private var usesImportantRanking: Bool {
    ["notice", "latest-news"].contains(selectedCategoryID)
  }

  var body: some View {
    List {
      Section {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(contentClient.categories) { category in
              Button {
                selectedCategoryID = category.id
                query = ""
                Task { await loadSelectedCategory() }
              } label: {
                CategoryChip(title: category.title, isSelected: category.id == selectedCategoryID)
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.vertical, 2)
        }
      }

      switch loadState {
      case .loading where displayedArticles.isEmpty:
        Section {
          ProgressView("正在从官网获取资讯")
            .frame(maxWidth: .infinity, minHeight: 120)
        }
      case .failed(let message) where displayedArticles.isEmpty:
        Section {
          ContentUnavailableView("加载失败", systemImage: "wifi.exclamationmark", description: Text(message))
        }
      default:
        if displayedArticles.isEmpty {
          Section {
            ContentUnavailableView("暂无内容", systemImage: "doc.text.magnifyingglass", description: Text("换个栏目或搜索关键词试试。"))
          }
        } else {
          if !pinnedArticles.isEmpty {
            Section("重要关注") {
              ForEach(pinnedArticles) { article in
                articleButton(article, pinned: true)
              }
            }
          }

          Section(selectedCategory.title) {
            ForEach(regularArticles) { article in
              articleButton(article, pinned: false)
            }
          }
        }
      }
    }
    .navigationTitle("资讯")
    .searchable(text: $query, prompt: "搜索高考、政策、报名")
    .onSubmit(of: .search) {
      Task { await searchOrFilter() }
    }
    .refreshable {
      await loadSelectedCategory()
    }
    .toolbar {
      Button {
        Task { await loadSelectedCategory() }
      } label: {
        Image(systemName: "arrow.clockwise")
      }
    }
    .task {
      if displayedArticles.isEmpty {
        await loadSelectedCategory()
      }
    }
  }

  @ViewBuilder
  private func articleButton(_ article: CachedArticle, pinned: Bool) -> some View {
    Button {
      router.navigate(to: .article(id: article.id))
    } label: {
      ArticleListRow(article: article, pinned: pinned)
    }
    .buttonStyle(.plain)
  }

  private func searchOrFilter() async {
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else {
      await loadSelectedCategory()
      return
    }

    loadState = .loading
    do {
      let results = try await contentClient.searchOfficialSite(query: term)
      results.forEach(upsert)
      try? modelContext.save()
      loadState = .loaded(ImportantNewsRanker.ranked(results))
    } catch {
      loadState = .failed(error.localizedDescription)
    }
  }

  private func loadSelectedCategory() async {
    loadState = .loading
    do {
      let articles = try await contentClient.rankedFeed(category: selectedCategory, limit: 40)
      articles.forEach(upsert)
      try? modelContext.save()
      loadState = .loaded(articles)
    } catch {
      loadState = .failed(error.localizedDescription)
    }
  }

  private func upsert(_ article: CachedArticle) {
    if let existing = cachedArticles.first(where: { $0.id == article.id }) {
      existing.update(from: article)
    } else {
      modelContext.insert(article)
    }
  }
}

private struct CategoryChip: View {
  let title: String
  let isSelected: Bool

  var body: some View {
    if isSelected {
      chip
        .foregroundStyle(.white)
        .glassEffect(.regular.tint(.blue.opacity(0.28)).interactive(), in: .rect(cornerRadius: 999))
    } else {
      chip
        .foregroundStyle(.primary)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 999))
    }
  }

  private var chip: some View {
    Text(title)
      .font(.subheadline.weight(.semibold))
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
  }
}

private struct ArticleListRow: View {
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
        } else if !article.attachments.isEmpty {
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
        if let publishedAt = article.publishedAt {
          Text(DateFormatters.displayDate.string(from: publishedAt))
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 6)
  }
}
