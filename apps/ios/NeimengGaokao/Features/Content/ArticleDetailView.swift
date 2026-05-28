import SwiftData
import SwiftUI

struct ArticleDetailView: View {
  let articleID: String

  @Environment(RouterPath.self) private var router
  @Environment(\.contentClient) private var contentClient
  @Environment(\.modelContext) private var modelContext

  @Query private var articles: [CachedArticle]
  @State private var fetchedDetail: CachedArticle?
  @State private var isLoading = false
  @State private var errorMessage: String?

  private var article: CachedArticle? {
    fetchedDetail ?? articles.first(where: { $0.id == articleID })
  }

  private var imageAttachments: [ArticleAttachment] {
    article?.attachments.filter { $0.fileType == "image" } ?? []
  }

  private var documentAttachments: [ArticleAttachment] {
    article?.attachments.filter { $0.fileType != "image" } ?? []
  }

  private var bodyParagraphs: [String] {
    guard let body = article?.body else { return [] }
    return body
      .components(separatedBy: "\n\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  var body: some View {
    Group {
      if let article {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            header(for: article)

            if isLoading {
              ProgressView("正在读取正文")
                .frame(maxWidth: .infinity, minHeight: 80)
            }

            if let errorMessage {
              Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
            }

            if !imageAttachments.isEmpty {
              VStack(alignment: .leading, spacing: 12) {
                Text("正文图片")
                  .font(.headline)
                ForEach(imageAttachments) { image in
                  ArticleRemoteImage(url: image.url, caption: image.title)
                }
              }
            }

            if bodyParagraphs.isEmpty {
              Text(article.summary.isEmpty ? "这条内容可能是附件或外链，请打开原文查看。" : article.summary)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(6)
            } else {
              VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(bodyParagraphs.enumerated()), id: \.offset) { _, paragraph in
                  Text(paragraph)
                    .font(.body)
                    .lineSpacing(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
              }
            }

            if !documentAttachments.isEmpty {
              VStack(alignment: .leading, spacing: 10) {
                Text("附件")
                  .font(.headline)
                ForEach(documentAttachments) { attachment in
                  Button {
                    router.navigate(to: .web(title: attachment.title, url: attachment.url))
                  } label: {
                    HStack(spacing: 12) {
                      Image(systemName: "doc")
                        .foregroundStyle(.blue)
                      VStack(alignment: .leading, spacing: 3) {
                        Text(attachment.title)
                          .font(.subheadline.weight(.semibold))
                          .foregroundStyle(.primary)
                        Text(attachment.fileType.uppercased())
                          .font(.caption)
                          .foregroundStyle(.secondary)
                      }
                      Spacer()
                      Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .nativeGlassPanel(cornerRadius: 16, tint: .blue.opacity(0.05), interactive: true)
                  }
                  .buttonStyle(.plain)
                }
              }
            }
          }
          .padding()
        }
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
              toggleFavorite(article)
            } label: {
              Image(systemName: article.isFavorite ? "star.fill" : "star")
            }
            Button {
              router.navigate(to: .web(title: "原文", url: article.originalURL))
            } label: {
              Image(systemName: "safari")
            }
          }
        }
        .refreshable {
          await loadDetailIfNeeded(article)
        }
        .task(id: article.id) {
          await loadDetailIfNeeded(article)
        }
      } else {
        ContentUnavailableView("找不到文章", systemImage: "doc.text.magnifyingglass")
      }
    }
  }

  @ViewBuilder
  private func header(for article: CachedArticle) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(article.title)
        .font(.title2.weight(.bold))
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 4) {
        if let publishedAt = article.publishedAt {
          Label(DateFormatters.displayDate.string(from: publishedAt), systemImage: "calendar")
        }
        if let source = article.source, !source.isEmpty {
          Label(source, systemImage: "building.2")
        }
        Label(article.categoryTitle, systemImage: "tag")
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .nativeGlassPanel(cornerRadius: 16, tint: .blue.opacity(0.05))
  }

  private func loadDetailIfNeeded(_ article: CachedArticle) async {
    guard !isLoading else { return }
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    do {
      let detail = try await contentClient.fetchArticle(from: article)
      if let existing = articles.first(where: { $0.id == detail.id }) {
        existing.update(from: detail)
      } else {
        modelContext.insert(detail)
      }
      try? modelContext.save()
      fetchedDetail = detail
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func toggleFavorite(_ article: CachedArticle) {
    article.isFavorite.toggle()
    try? modelContext.save()
  }
}
