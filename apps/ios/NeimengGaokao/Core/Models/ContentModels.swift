import Foundation
import SwiftData

enum ContentKind: String, Codable, CaseIterable, Identifiable {
  case latest
  case news
  case notice
  case policy
  case topic
  case service

  var id: String { rawValue }

  var title: String {
    switch self {
    case .latest: "最新"
    case .news: "新闻"
    case .notice: "公告"
    case .policy: "政策"
    case .topic: "专题"
    case .service: "服务"
    }
  }
}

struct OfficialCategory: Identifiable, Hashable {
  let id: String
  let title: String
  let kind: ContentKind
  let examType: String?
  let url: URL
}

struct ArticleAttachment: Identifiable, Hashable, Codable {
  let id: UUID
  let title: String
  let url: URL
  let fileType: String

  init(id: UUID = UUID(), title: String, url: URL, fileType: String) {
    self.id = id
    self.title = title
    self.url = url
    self.fileType = fileType
  }
}

@Model
final class CachedCategory {
  @Attribute(.unique) var id: String
  var title: String
  var kindRawValue: String
  var examType: String?
  var urlString: String

  init(id: String, title: String, kind: ContentKind, examType: String?, url: URL) {
    self.id = id
    self.title = title
    self.kindRawValue = kind.rawValue
    self.examType = examType
    self.urlString = url.absoluteString
  }

  var kind: ContentKind { ContentKind(rawValue: kindRawValue) ?? .latest }
  var url: URL { URL(string: urlString) ?? URL(string: "https://www.nm.zsks.cn/")! }
}

@Model
final class CachedArticle {
  @Attribute(.unique) var id: String
  var categoryID: String
  var categoryTitle: String
  var kindRawValue: String
  var title: String
  var summary: String
  var body: String
  var source: String?
  var publishedAt: Date?
  var originalURLString: String
  var attachmentData: Data
  var isFavorite: Bool
  var cachedAt: Date

  init(
    id: String,
    categoryID: String,
    categoryTitle: String,
    kind: ContentKind,
    title: String,
    summary: String = "",
    body: String = "",
    source: String? = nil,
    publishedAt: Date? = nil,
    originalURL: URL,
    attachments: [ArticleAttachment] = [],
    isFavorite: Bool = false,
    cachedAt: Date = .now
  ) {
    self.id = id
    self.categoryID = categoryID
    self.categoryTitle = categoryTitle
    self.kindRawValue = kind.rawValue
    self.title = title
    self.summary = summary
    self.body = body
    self.source = source
    self.publishedAt = publishedAt
    self.originalURLString = originalURL.absoluteString
    self.attachmentData = (try? JSONEncoder().encode(attachments)) ?? Data()
    self.isFavorite = isFavorite
    self.cachedAt = cachedAt
  }

  var kind: ContentKind { ContentKind(rawValue: kindRawValue) ?? .latest }
  var originalURL: URL { URL(string: originalURLString) ?? URL(string: "https://www.nm.zsks.cn/")! }
  var attachments: [ArticleAttachment] {
    (try? JSONDecoder().decode([ArticleAttachment].self, from: attachmentData)) ?? []
  }

  func update(from article: CachedArticle) {
    categoryID = article.categoryID
    categoryTitle = article.categoryTitle
    kindRawValue = article.kindRawValue
    title = article.title
    summary = article.summary
    body = article.body
    source = article.source
    publishedAt = article.publishedAt
    originalURLString = article.originalURLString
    attachmentData = article.attachmentData
    cachedAt = .now
  }
}

@Model
final class CachedServiceLink {
  @Attribute(.unique) var id: String
  var title: String
  var subtitle: String
  var urlString: String
  var examType: String?
  var requiresLogin: Bool
  var priority: Int

  init(
    id: String,
    title: String,
    subtitle: String,
    url: URL,
    examType: String? = nil,
    requiresLogin: Bool,
    priority: Int = 100
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.urlString = url.absoluteString
    self.examType = examType
    self.requiresLogin = requiresLogin
    self.priority = priority
  }

  var url: URL { URL(string: urlString) ?? URL(string: "https://www.nm.zsks.cn/")! }
}

@Model
final class CandidateProfile {
  @Attribute(.unique) var id: UUID
  var displayName: String
  var idNumberLast4: String
  var examType: String
  var createdAt: Date

  init(id: UUID = UUID(), displayName: String, idNumberLast4: String, examType: String) {
    self.id = id
    self.displayName = displayName
    self.idNumberLast4 = idNumberLast4
    self.examType = examType
    self.createdAt = .now
  }
}
