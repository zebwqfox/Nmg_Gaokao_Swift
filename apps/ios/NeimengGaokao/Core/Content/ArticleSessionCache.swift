import Foundation

/// 当前 App 会话内的资讯详情缓存，不写入 SwiftData。
@MainActor
enum ArticleSessionCache {
  private static var store: [String: CachedArticle] = [:]

  static func store(_ article: CachedArticle) {
    store[article.id] = article
  }

  static func get(_ id: String) -> CachedArticle? {
    store[id]
  }

  static func replace(_ article: CachedArticle) {
    store[article.id] = article
  }

  static var allArticles: [CachedArticle] {
    store.values.sorted { lhs, rhs in
      let left = lhs.publishedAt ?? lhs.cachedAt
      let right = rhs.publishedAt ?? rhs.cachedAt
      return left > right
    }
  }
}
