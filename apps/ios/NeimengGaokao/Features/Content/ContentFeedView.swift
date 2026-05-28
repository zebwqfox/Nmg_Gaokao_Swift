import SwiftData
import SwiftUI

struct ContentFeedView: View {
  @Environment(RouterPath.self) private var router
  @Environment(\.contentClient) private var contentClient
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \CachedArticle.cachedAt, order: .reverse) private var cachedArticles: [CachedArticle]

  @State private var selectedCategoryID = "notice"
  @State private var query = ""
  @State private var feedItems: [CachedArticle] = []
  @State private var nextPage = 1
  @State private var hasMorePages = true
  @State private var isRefreshing = false
  @State private var isLoadingMore = false
  @State private var errorMessage: String?
  @State private var isSearchMode = false
  @State private var activeSearchTerm: String?

  private var selectedCategory: OfficialCategory {
    contentClient.categories.first(where: { $0.id == selectedCategoryID }) ?? contentClient.categories[0]
  }

  private var displayedArticles: [CachedArticle] {
    if isSearchMode {
      return ImportantNewsRanker.ranked(feedItems)
    }
    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return ImportantNewsRanker.ranked(feedItems)
    }
    return ImportantNewsRanker.ranked(
      feedItems.filter { article in
        article.title.localizedCaseInsensitiveContains(query)
          || article.summary.localizedCaseInsensitiveContains(query)
      }
    )
  }

  private var pinnedArticles: [CachedArticle] {
    ImportantNewsRanker.pinned(displayedArticles)
  }

  private var regularArticles: [CachedArticle] {
    ImportantNewsRanker.regular(from: displayedArticles)
  }

  var body: some View {
    List {
      Section {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(contentClient.categories) { category in
              Button {
                guard selectedCategoryID != category.id else { return }
                selectedCategoryID = category.id
                query = ""
                isSearchMode = false
                Task { await reloadFeed() }
              } label: {
                CategoryChip(title: category.title, isSelected: category.id == selectedCategoryID)
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.vertical, 2)
        }
      }

      if isRefreshing, feedItems.isEmpty {
        Section {
          ProgressView("正在从官网获取资讯")
            .frame(maxWidth: .infinity, minHeight: 120)
        }
      } else if let errorMessage, feedItems.isEmpty {
        Section {
          ContentUnavailableView("加载失败", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
        }
      } else if displayedArticles.isEmpty {
        Section {
          ContentUnavailableView("暂无内容", systemImage: "doc.text.magnifyingglass", description: Text("换个栏目或搜索关键词试试。"))
        }
      } else {
        if !pinnedArticles.isEmpty {
          Section("重要关注") {
            ForEach(pinnedArticles) { article in
              articleRow(article, pinned: true)
            }
          }
        }

        Section(isSearchMode ? "搜索结果" : selectedCategory.title) {
          ForEach(regularArticles) { article in
            articleRow(article, pinned: false)
              .onAppear {
                loadNextPageIfNeeded(current: article)
              }
          }

          if isLoadingMore {
            HStack {
              Spacer()
              ProgressView("加载更多")
              Spacer()
            }
            .listRowSeparator(.hidden)
          } else if !hasMorePages, !feedItems.isEmpty {
            Text("没有更多了")
              .font(.footnote)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
              .listRowSeparator(.hidden)
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
      if isSearchMode, let term = activeSearchTerm {
        query = term
        await searchOrFilter()
      } else {
        await reloadFeed()
      }
    }
    .toolbar {
      Button {
        Task { await reloadFeed() }
      } label: {
        Image(systemName: "arrow.clockwise")
      }
    }
    .task {
      if feedItems.isEmpty {
        await reloadFeed()
      }
    }
  }

  @ViewBuilder
  private func articleRow(_ article: CachedArticle, pinned: Bool) -> some View {
    Button {
      router.navigate(to: .article(id: article.id))
    } label: {
      ArticleListRow(article: article, pinned: pinned)
    }
    .buttonStyle(.plain)
  }

  private func loadNextPageIfNeeded(current: CachedArticle) {
    guard hasMorePages, !isRefreshing, !isLoadingMore else { return }
    guard current.id == regularArticles.last?.id else { return }
    Task {
      if isSearchMode {
        await loadNextSearchPage()
      } else {
        await loadNextPage()
      }
    }
  }

  private func reloadFeed() async {
    isSearchMode = false
    activeSearchTerm = nil
    nextPage = 1
    hasMorePages = true
    feedItems = []
    errorMessage = nil
    isRefreshing = true
    defer { isRefreshing = false }
    await loadNextPage()
  }

  private func loadNextPage() async {
    guard hasMorePages, !isLoadingMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }

    do {
      let result = try await contentClient.fetchFeedPage(
        category: selectedCategory,
        page: nextPage,
        perPageLimit: 30
      )
      result.articles.forEach(upsert)
      try? modelContext.save()
      feedItems = mergeArticles(feedItems, with: result.articles)
      hasMorePages = result.hasMore
      nextPage = result.page + 1
      errorMessage = nil
    } catch {
      if feedItems.isEmpty {
        errorMessage = error.localizedDescription
      }
      hasMorePages = false
    }
  }

  private func searchOrFilter() async {
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else {
      await reloadFeed()
      return
    }

    isSearchMode = true
    activeSearchTerm = term
    nextPage = 1
    hasMorePages = true
    feedItems = []
    errorMessage = nil
    isRefreshing = true
    defer { isRefreshing = false }
    await loadNextSearchPage()
  }

  private func loadNextSearchPage() async {
    guard let term = activeSearchTerm, !term.isEmpty else { return }
    guard hasMorePages, !isLoadingMore else { return }

    isLoadingMore = true
    defer { isLoadingMore = false }

    do {
      let result = try await contentClient.searchOfficialSitePage(
        query: term,
        page: nextPage,
        perPageLimit: 20
      )
      result.articles.forEach(upsert)
      try? modelContext.save()
      feedItems = mergeArticles(feedItems, with: result.articles)
      hasMorePages = result.hasMore
      nextPage = result.page + 1
      errorMessage = nil
    } catch {
      if feedItems.isEmpty {
        errorMessage = error.localizedDescription
      }
      hasMorePages = false
    }
  }

  private func mergeArticles(_ existing: [CachedArticle], with incoming: [CachedArticle]) -> [CachedArticle] {
    var seen = Set(existing.map(\.id))
    var merged = existing
    for article in incoming where seen.insert(article.id).inserted {
      merged.append(article)
    }
    return ImportantNewsRanker.ranked(merged)
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
