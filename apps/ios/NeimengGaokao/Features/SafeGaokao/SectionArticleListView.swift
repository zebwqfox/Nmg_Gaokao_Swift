import SwiftUI

struct SectionArticleListView: View {
  let category: OfficialCategory

  @Environment(RouterPath.self) private var router
  @Environment(\.contentClient) private var contentClient

  @State private var articles: [CachedArticle] = []
  @State private var nextPage = 1
  @State private var hasMore = true
  @State private var isRefreshing = false
  @State private var isLoadingMore = false
  @State private var loadMoreTask: Task<Void, Never>?
  @State private var errorMessage: String?

  var body: some View {
    List {
      if isRefreshing, articles.isEmpty {
        ProgressView("正在加载")
          .frame(maxWidth: .infinity, minHeight: 120)
          .listRowSeparator(.hidden)
      } else if let errorMessage, articles.isEmpty {
        ContentUnavailableView(
          "加载失败",
          systemImage: "wifi.exclamationmark",
          description: Text(errorMessage)
        )
        .listRowSeparator(.hidden)
      } else if articles.isEmpty {
        ContentUnavailableView(
          "暂无内容",
          systemImage: "doc.text.magnifyingglass"
        )
        .listRowSeparator(.hidden)
      } else {
        ForEach(articles) { article in
          Button {
            ArticleSessionCache.store(article)
            router.navigate(to: .article(id: article.id))
          } label: {
            FeedArticleRow(article: article, pinned: false)
          }
          .buttonStyle(.plain)
          .onAppear { loadMoreIfNeeded(current: article) }
        }

        FeedLoadMoreFooter(isLoading: isLoadingMore, hasMore: hasMore)
          .listRowSeparator(.hidden)
          .onAppear { triggerLoadMore() }
      }
    }
    .navigationTitle(category.title)
    .navigationBarTitleDisplayMode(.large)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          router.navigate(to: .web(title: category.title, url: category.url))
        } label: {
          Image(systemName: "safari")
        }
      }
    }
    .refreshable { await reload() }
    .task { await reload() }
  }

  private func reload() async {
    guard !isRefreshing else { return }
    loadMoreTask?.cancel()
    loadMoreTask = nil
    nextPage = 1
    hasMore = true
    errorMessage = nil
    isRefreshing = true
    defer { isRefreshing = false }
    do {
      let result = try await contentClient.fetchFeedPage(
        category: category, page: 1, perPageLimit: 20
      )
      articles = result.articles
      hasMore = result.hasMore
      nextPage = 2
      result.articles.forEach(ArticleSessionCache.store)
    } catch {
      if articles.isEmpty { errorMessage = error.localizedDescription }
    }
  }

  private func loadPage() async {
    guard hasMore, !isLoadingMore, !isRefreshing else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    let page = nextPage
    do {
      let result = try await contentClient.fetchFeedPage(
        category: category, page: page, perPageLimit: 20
      )
      let existing = Set(articles.map(\.id))
      let fresh = result.articles.filter { !existing.contains($0.id) }
      articles.append(contentsOf: fresh)
      hasMore = result.hasMore
      nextPage = result.page + 1
      fresh.forEach(ArticleSessionCache.store)
    } catch {
      hasMore = false
    }
  }

  private func loadMoreIfNeeded(current: CachedArticle) {
    guard hasMore, !isRefreshing, !isLoadingMore else { return }
    guard let index = articles.firstIndex(where: { $0.id == current.id }),
          index >= max(articles.count - 4, 0)
    else { return }
    triggerLoadMore()
  }

  private func triggerLoadMore() {
    guard hasMore, !isRefreshing, !isLoadingMore, loadMoreTask == nil else { return }
    loadMoreTask = Task {
      defer { loadMoreTask = nil }
      await loadPage()
    }
  }
}
