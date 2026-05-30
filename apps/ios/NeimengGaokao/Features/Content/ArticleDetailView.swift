import SwiftUI
import UIKit

struct ArticleDetailView: View {
  let articleID: String

  @Environment(RouterPath.self) private var router
  @Environment(\.contentClient) private var contentClient
  @Environment(\.openURL) private var openURL

  @State private var article: CachedArticle?
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var isFavorite = false
  @State private var attachmentError: String?
  @State private var isGeneratingShareImage = false
  @State private var shareImageItem: ShareableImageItem?
  @State private var showCopyToast = false

  private var documentAttachments: [ArticleAttachment] {
    article?.documentAttachments ?? []
  }

  private var hasRenderedBody: Bool {
    guard let article else { return false }
    return !article.contentBlocks.isEmpty
      || !article.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var showsInlineLoadingBar: Bool {
    isLoading && !hasRenderedBody
  }

  var body: some View {
    Group {
      if let currentArticle = article {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            header(for: currentArticle)

            if showsInlineLoadingBar {
              FeedInlineLoadingBar(message: "正在读取正文，文字将优先显示")
            } else if isLoading {
              FeedInlineLoadingBar(message: "正在更新正文")
            }

            if let errorMessage {
              Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
            }

            if let attachmentError {
              Text(attachmentError)
                .font(.footnote)
                .foregroundStyle(.orange)
            }

            articleBody(for: currentArticle)
              .animation(.easeOut(duration: 0.25), value: currentArticle.contentBlocks.count)
              .animation(.easeOut(duration: 0.25), value: currentArticle.body.count)

            if !documentAttachments.isEmpty {
              VStack(alignment: .leading, spacing: 10) {
                Text("附件")
                  .font(.headline)
                ForEach(documentAttachments) { attachment in
                  Button {
                    openAttachment(attachment)
                  } label: {
                    HStack(spacing: 12) {
                      Image(systemName: attachment.systemImageName)
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
                      Image(systemName: "arrow.up.forward.square")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .nativeGlassPanel(cornerRadius: 16, tint: .blue.opacity(0.05), interactive: true)
                  }
                  .buttonStyle(.plain)
                }
              }
              .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
          }
          .padding()
        }
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
              isFavorite = FavoriteArticles.toggle(articleID)
            } label: {
              Image(systemName: isFavorite ? "star.fill" : "star")
            }
            Menu {
              Button {
                Task { await generateShareImage(for: currentArticle) }
              } label: {
                Label("生成长图分享", systemImage: "photo.on.rectangle.angled")
              }
              Button {
                copyArticleText(currentArticle)
              } label: {
                Label("复制全文", systemImage: "doc.on.doc")
              }
              Button {
                router.navigate(to: .web(title: "原文", url: currentArticle.originalURL))
              } label: {
                Label("在浏览器打开原文", systemImage: "safari")
              }
              ShareLink(item: currentArticle.originalURL) {
                Label("分享链接", systemImage: "link")
              }
            } label: {
              Image(systemName: "square.and.arrow.up")
            }
          }
        }
        .refreshable {
          await loadDetailIfNeeded(force: true)
        }
        .sheet(item: $shareImageItem) { item in
          ActivityShareSheet(items: [item.image])
        }
        .overlay {
          if isGeneratingShareImage {
            shareImageProgressOverlay
          }
        }
        .overlay(alignment: .bottom) {
          if showCopyToast {
            copyToast
          }
        }
      } else if isLoading {
        ProgressView("正在加载文章")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView("找不到文章", systemImage: "doc.text.magnifyingglass")
      }
    }
    .task(id: articleID) {
      isFavorite = FavoriteArticles.contains(articleID)
      if article == nil {
        article = ArticleSessionCache.get(articleID)
      }
      await loadDetailIfNeeded(force: false)
    }
  }

  @ViewBuilder
  private func articleBody(for article: CachedArticle) -> some View {
    if !article.contentBlocks.isEmpty {
      VStack(alignment: .leading, spacing: 14) {
        ForEach(Array(article.contentBlocks.enumerated()), id: \.offset) { _, block in
          switch block {
          case .text(let paragraph):
            Text(paragraph)
              .font(.body)
              .lineSpacing(7)
              .frame(maxWidth: .infinity, alignment: .leading)
              .textSelection(.enabled)
              .contextMenu {
                Button {
                  copyText(paragraph)
                } label: {
                  Label("复制本段", systemImage: "doc.on.doc")
                }
              }
          case .remoteImage(let url, let caption):
            ArticleRemoteImage(url: url, caption: caption, referer: article.originalURL)
          case .inlineImagePayload(let payload, let caption):
            ArticleRemoteImage(inlinePayload: payload, caption: caption)
          case .inlineImage(let data, let caption):
            ArticleRemoteImage(inlineData: data, caption: caption)
          case .table(let rows):
            ArticleTableView(rows: rows)
          }
        }
      }
    } else if bodyParagraphs(for: article).isEmpty {
      if !article.summary.isEmpty {
        Text(article.summary)
          .font(.body)
          .foregroundStyle(isLoading ? .secondary : .primary)
          .lineSpacing(6)
      } else {
        Text("这条内容可能是附件或外链，请打开原文查看。")
          .font(.body)
          .foregroundStyle(.secondary)
          .lineSpacing(6)
      }
    } else {
      VStack(alignment: .leading, spacing: 14) {
        ForEach(Array(bodyParagraphs(for: article).enumerated()), id: \.offset) { _, paragraph in
          Text(paragraph)
            .font(.body)
            .lineSpacing(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .contextMenu {
              Button {
                copyText(paragraph)
              } label: {
                Label("复制本段", systemImage: "doc.on.doc")
              }
            }
        }
      }
    }
  }

  private func bodyParagraphs(for article: CachedArticle) -> [String] {
    article.body
      .components(separatedBy: "\n\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  @ViewBuilder
  private func header(for article: CachedArticle) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(article.title)
        .font(.title2.weight(.bold))
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .contextMenu {
          Button {
            copyText(article.title)
          } label: {
            Label("复制标题", systemImage: "doc.on.doc")
          }
        }

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

  private func loadDetailIfNeeded(force: Bool) async {
    guard let current = article ?? ArticleSessionCache.get(articleID) else {
      errorMessage = "未找到这篇文章，请返回列表后重试。"
      return
    }

    article = current
    let hasBody = !current.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !current.contentBlocks.isEmpty
    guard force || !hasBody else { return }

    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    do {
      let detail = try await contentClient.fetchArticle(from: current)
      if Task.isCancelled { return }
      ArticleSessionCache.replace(detail)
      withAnimation(.easeOut(duration: 0.25)) {
        article = detail
      }
    } catch is CancellationError {
      return
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func openAttachment(_ attachment: ArticleAttachment) {
    attachmentError = nil
    openURL(attachment.url) { accepted in
      if !accepted {
        attachmentError = "无法打开附件，请稍后重试或使用原文链接。"
      }
    }
  }

  // MARK: - 分享与复制

  private func generateShareImage(for article: CachedArticle) async {
    guard !isGeneratingShareImage else { return }
    isGeneratingShareImage = true
    defer { isGeneratingShareImage = false }

    let blocks = await ArticleShareImageRenderer.makeShareBlocks(for: article)
    guard !Task.isCancelled else { return }

    if let image = ArticleShareImageRenderer.render(article: article, blocks: blocks) {
      shareImageItem = ShareableImageItem(image: image)
    } else {
      errorMessage = "生成长图失败，请稍后重试。"
    }
  }

  private func copyArticleText(_ article: CachedArticle) {
    var parts: [String] = [article.title]
    if !article.contentBlocks.isEmpty {
      for block in article.contentBlocks {
        switch block {
        case .text(let text):
          parts.append(text)
        case .table(let rows):
          parts.append(rows.map { $0.joined(separator: "\t") }.joined(separator: "\n"))
        default:
          break
        }
      }
    } else {
      parts.append(article.body)
    }
    copyText(parts.joined(separator: "\n\n"))
  }

  private func copyText(_ text: String) {
    UIPasteboard.general.string = text
    withAnimation(.easeOut(duration: 0.2)) { showCopyToast = true }
    Task {
      try? await Task.sleep(nanoseconds: 1_400_000_000)
      withAnimation(.easeIn(duration: 0.2)) { showCopyToast = false }
    }
  }

  private var shareImageProgressOverlay: some View {
    ZStack {
      Color.black.opacity(0.25).ignoresSafeArea()
      VStack(spacing: 12) {
        ProgressView()
        Text("正在生成长图…")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .padding(24)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .transition(.opacity)
  }

  private var copyToast: some View {
    Label("已复制", systemImage: "checkmark.circle.fill")
      .font(.subheadline.weight(.semibold))
      .padding(.horizontal, 18)
      .padding(.vertical, 10)
      .background(.regularMaterial, in: Capsule())
      .padding(.bottom, 32)
      .transition(.opacity.combined(with: .move(edge: .bottom)))
  }
}
