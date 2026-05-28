import SwiftUI

struct ContentFeedView: View {
  @Environment(RouterPath.self) private var router
  @Environment(\.contentClient) private var contentClient

  @State private var selectedCategoryID = "notice"
  @State private var feedItems: [CachedArticle] = []
  @State private var nextPage = 1
  @State private var hasMorePages = true
  @State private var isRefreshing = false
  @State private var isLoadingMore = false
  @State private var errorMessage: String?
  @State private var feedLoadGeneration = 0
  @State private var loadMoreTask: Task<Void, Never>?
  @State private var feedHeadIDs: Set<String> = []
  @State private var loadedCategoryID: String?

  private var selectedCategory: OfficialCategory {
    contentClient.categories.first(where: { $0.id == selectedCategoryID }) ?? contentClient.categories[0]
  }

  private var pinnedArticles: [CachedArticle] {
    ImportantNewsRanker.sortedByDate(
      feedItems.filter { feedHeadIDs.contains($0.id) && ImportantNewsRanker.isPinned($0) }
    )
  }

  private var regularArticles: [CachedArticle] {
    let pinnedIDs = Set(pinnedArticles.map(\.id))
    return feedItems.filter { !pinnedIDs.contains($0.id) }
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
      } else if feedItems.isEmpty {
        Section {
          ContentUnavailableView(
            "暂无内容",
            systemImage: "doc.text.magnifyingglass",
            description: Text("换个栏目试试，或使用搜索页查找关键词。")
          )
        }
      } else {
        if !pinnedArticles.isEmpty {
          Section("重要关注") {
            ForEach(pinnedArticles) { article in
              articleRow(article, pinned: true)
            }
          }
        }

        Section(selectedCategory.title) {
          ForEach(regularArticles) { article in
            articleRow(article, pinned: false)
              .transition(.opacity.combined(with: .move(edge: .bottom)))
              .onAppear {
                loadNextPageIfNeeded(current: article)
              }
          }

          if hasMorePages {
            Color.clear
              .frame(height: 48)
              .listRowSeparator(.hidden)
              .onAppear {
                loadMoreFromBottom()
              }
          }

          FeedLoadMoreFooter(isLoading: isLoadingMore, hasMore: hasMorePages)
            .listRowSeparator(.hidden)
        }
      }
    }
    .navigationTitle("资讯")
    .refreshable {
      await reloadFeed()
    }
    .toolbar {
      Button {
        Task { await reloadFeed() }
      } label: {
        Image(systemName: "arrow.clockwise")
      }
    }
    .task(id: selectedCategoryID) {
      if loadedCategoryID == selectedCategoryID, !feedItems.isEmpty {
        return
      }
      loadedCategoryID = selectedCategoryID
      await reloadFeed()
    }
  }

  @ViewBuilder
  private func articleRow(_ article: CachedArticle, pinned: Bool) -> some View {
    Button {
      ArticleSessionCache.store(article)
      router.navigate(to: .article(id: article.id))
    } label: {
      FeedArticleRow(article: article, pinned: pinned)
    }
    .buttonStyle(.plain)
  }

  private func loadNextPageIfNeeded(current: CachedArticle) {
    guard hasMorePages, !isRefreshing, !isLoadingMore else { return }
    let regular = regularArticles
    guard let index = regular.firstIndex(where: { $0.id == current.id }),
          index >= max(regular.count - 5, 0)
    else { return }
    loadMoreFromBottom()
  }

  private func loadMoreFromBottom() {
    guard hasMorePages, !isRefreshing, !isLoadingMore else { return }
    guard loadMoreTask == nil else { return }

    loadMoreTask = Task {
      defer { loadMoreTask = nil }
      await loadNextPage()
    }
  }

  private func reloadFeed() async {
    feedLoadGeneration += 1
    let generation = feedLoadGeneration
    nextPage = 1
    hasMorePages = true
    feedItems = []
    feedHeadIDs = []
    errorMessage = nil
    isRefreshing = true
    defer { isRefreshing = false }
    await loadNextPage(generation: generation, replacing: true)
  }

  private func loadNextPage(generation: Int? = nil, replacing: Bool = false) async {
    let generation = generation ?? feedLoadGeneration
    guard generation == feedLoadGeneration else { return }
    guard hasMorePages, !isLoadingMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }

    let pageToLoad = nextPage
    do {
      let result = try await contentClient.fetchFeedPage(
        category: selectedCategory,
        page: pageToLoad,
        perPageLimit: 30
      )
      guard generation == feedLoadGeneration else { return }
      if replacing || pageToLoad == 1 {
        withAnimation(.easeInOut(duration: 0.24)) {
          feedItems = result.articles
          feedHeadIDs = Set(result.articles.map(\.id))
        }
      } else {
        withAnimation(.easeInOut(duration: 0.24)) {
          feedItems = mergeArticles(feedItems, with: result.articles)
        }
      }
      hasMorePages = result.hasMore
      nextPage = result.page + 1
      errorMessage = nil
      result.articles.forEach(ArticleSessionCache.store)
    } catch {
      guard generation == feedLoadGeneration else { return }
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
    return merged
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
