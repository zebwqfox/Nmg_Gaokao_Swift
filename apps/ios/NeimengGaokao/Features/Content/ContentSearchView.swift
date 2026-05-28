import SwiftUI

struct ContentSearchView: View {
  @Environment(RouterPath.self) private var router
  @Environment(\.contentClient) private var contentClient

  @State private var query = ""
  @State private var results: [CachedArticle] = []
  @State private var nextPage = 1
  @State private var hasMorePages = true
  @State private var isRefreshing = false
  @State private var isLoadingMore = false
  @State private var errorMessage: String?
  @State private var activeSearchTerm: String?
  @State private var searchGeneration = 0
  @State private var searchTask: Task<Void, Never>?
  @State private var loadMoreTask: Task<Void, Never>?

  private var trimmedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var awaitingOfficialSearch: Bool {
    !trimmedQuery.isEmpty && activeSearchTerm != trimmedQuery
  }

  var body: some View {
    List {
      if trimmedQuery.isEmpty {
        Section {
          ContentUnavailableView(
            "搜索官网资讯",
            systemImage: "magnifyingglass",
            description: Text("输入关键词搜索通知公告、政策解读和报名相关信息。")
          )
          .frame(maxWidth: .infinity, minHeight: 220)
        }
      } else if awaitingOfficialSearch || (isRefreshing && results.isEmpty) {
        Section {
          ProgressView(awaitingOfficialSearch && !isRefreshing ? "准备搜索官网" : "正在搜索官网")
            .frame(maxWidth: .infinity, minHeight: 120)
        }
      } else if let errorMessage, results.isEmpty {
        Section {
          ContentUnavailableView("搜索失败", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
        }
      } else if results.isEmpty {
        Section {
          ContentUnavailableView(
            "未找到相关内容",
            systemImage: "doc.text.magnifyingglass",
            description: Text("换个关键词试试。")
          )
        }
      } else {
        Section("搜索结果") {
          ForEach(results) { article in
            articleRow(article)
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
    .navigationTitle("搜索")
    .searchable(text: $query, prompt: "搜索高考、政策、报名")
    .onSubmit(of: .search) {
      searchTask?.cancel()
      Task { await performSearch() }
    }
    .onChange(of: query) { _, _ in
      scheduleOfficialSearch()
    }
    .refreshable {
      await refreshSearch()
    }
  }

  @ViewBuilder
  private func articleRow(_ article: CachedArticle) -> some View {
    Button {
      ArticleSessionCache.store(article)
      router.navigate(to: .article(id: article.id))
    } label: {
      FeedArticleRow(article: article, pinned: false)
    }
    .buttonStyle(.plain)
  }

  private func loadNextPageIfNeeded(current: CachedArticle) {
    guard hasMorePages, !isRefreshing, !isLoadingMore else { return }
    guard let index = results.firstIndex(where: { $0.id == current.id }),
          index >= max(results.count - 5, 0)
    else { return }
    loadMoreFromBottom()
  }

  private func loadMoreFromBottom() {
    guard hasMorePages, !isRefreshing, !isLoadingMore else { return }
    guard loadMoreTask == nil else { return }

    loadMoreTask = Task {
      defer { loadMoreTask = nil }
      await loadNextSearchPage()
    }
  }

  private func scheduleOfficialSearch() {
    searchTask?.cancel()

    let term = trimmedQuery
    guard !term.isEmpty else {
      if activeSearchTerm != nil {
        resetSearchState()
      }
      return
    }

    searchTask = Task {
      try? await Task.sleep(nanoseconds: 450_000_000)
      guard !Task.isCancelled else { return }
      await performSearch()
    }
  }

  private func refreshSearch() async {
    guard let term = activeSearchTerm, !term.isEmpty else { return }
    query = term
    await performSearch(force: true)
  }

  private func performSearch(force: Bool = false) async {
    let term = trimmedQuery
    guard !term.isEmpty else {
      resetSearchState()
      return
    }

    if !force, activeSearchTerm == term, !results.isEmpty, !isRefreshing {
      return
    }

    searchGeneration += 1
    let generation = searchGeneration
    activeSearchTerm = term
    nextPage = 1
    hasMorePages = true
    results = []
    errorMessage = nil
    isRefreshing = true
    defer { isRefreshing = false }
    await loadNextSearchPage(generation: generation, replacing: true)
  }

  private func loadNextSearchPage(generation: Int? = nil, replacing: Bool = false) async {
    guard let term = activeSearchTerm, !term.isEmpty else { return }
    let generation = generation ?? searchGeneration
    guard generation == searchGeneration else { return }
    guard hasMorePages, !isLoadingMore else { return }

    isLoadingMore = true
    defer { isLoadingMore = false }

    let pageToLoad = nextPage
    do {
      let result = try await contentClient.searchOfficialSitePage(
        query: term,
        page: pageToLoad,
        perPageLimit: 20
      )
      guard generation == searchGeneration else { return }
      if replacing || pageToLoad == 1 {
        withAnimation(.easeInOut(duration: 0.24)) {
          results = ImportantNewsRanker.sortedByDate(result.articles)
        }
      } else {
        withAnimation(.easeInOut(duration: 0.24)) {
          results = mergeArticles(results, with: result.articles)
        }
      }
      hasMorePages = result.hasMore
      nextPage = result.page + 1
      errorMessage = nil
      result.articles.forEach(ArticleSessionCache.store)
    } catch {
      guard generation == searchGeneration else { return }
      if results.isEmpty {
        errorMessage = error.localizedDescription
      }
      hasMorePages = false
    }
  }

  private func resetSearchState() {
    searchGeneration += 1
    activeSearchTerm = nil
    nextPage = 1
    hasMorePages = true
    results = []
    errorMessage = nil
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
