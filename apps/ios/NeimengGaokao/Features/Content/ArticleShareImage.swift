import SwiftUI
import UIKit

/// 用于长图分享的渲染块：图片在生成长图前已预加载为 UIImage。
enum ArticleShareBlock: Identifiable {
  case text(String)
  case image(UIImage)
  case table([[String]])

  var id: String {
    switch self {
    case .text(let value): return "t-\(value.hashValue)"
    case .image(let image): return "i-\(ObjectIdentifier(image).hashValue)"
    case .table(let rows): return "g-\(rows.count)-\(rows.first?.count ?? 0)-\(rows.hashValue)"
    }
  }
}

enum ArticleShareImageRenderer {
  /// 预加载正文图片并把内容块转换成可直接渲染的分享块。
  static func makeShareBlocks(for article: CachedArticle) async -> [ArticleShareBlock] {
    var blocks: [ArticleShareBlock] = []
    for block in article.contentBlocks {
      switch block {
      case .text(let text):
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { blocks.append(.text(trimmed)) }
      case .table(let rows):
        blocks.append(.table(rows))
      case .remoteImage(let url, _):
        if let image = await OfficialImageLoader.load(from: url, referer: article.originalURL) {
          blocks.append(.image(image))
        }
      case .inlineImagePayload(let payload, _):
        if let image = decodeInlineImage(payload) {
          blocks.append(.image(image))
        }
      case .inlineImage(let data, _):
        if let image = UIImage(data: data) {
          blocks.append(.image(image))
        }
      }
    }

    if blocks.isEmpty {
      let fallback = article.body
        .components(separatedBy: "\n\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      blocks = fallback.map { .text($0) }
    }
    return blocks
  }

  /// 把分享视图渲染成一张高清长图。
  @MainActor
  static func render(article: CachedArticle, blocks: [ArticleShareBlock], width: CGFloat = 390) -> UIImage? {
    let view = ShareableArticleView(article: article, blocks: blocks, width: width)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 3
    renderer.proposedSize = ProposedViewSize(width: width, height: nil)
    return renderer.uiImage
  }

  private static func decodeInlineImage(_ src: String) -> UIImage? {
    let trimmed = src.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.lowercased().hasPrefix("data:") {
      guard let comma = trimmed.firstIndex(of: ",") else { return nil }
      let payload = String(trimmed[trimmed.index(after: comma)...])
      guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else { return nil }
      return UIImage(data: data)
    }
    guard let data = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters) else { return nil }
    return UIImage(data: data)
  }
}

/// 长图分享的静态版式：标题 + 元信息 + 正文 + 来源水印。
struct ShareableArticleView: View {
  let article: CachedArticle
  let blocks: [ArticleShareBlock]
  let width: CGFloat

  private var contentWidth: CGFloat { width - 40 }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 10) {
        Text(article.title)
          .font(.title3.weight(.bold))
          .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 12) {
          if let publishedAt = article.publishedAt {
            Label(DateFormatters.displayDate.string(from: publishedAt), systemImage: "calendar")
          }
          if let source = article.source, !source.isEmpty {
            Label(source, systemImage: "building.2")
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        Divider()
      }

      ForEach(blocks) { block in
        switch block {
        case .text(let text):
          Text(text)
            .font(.callout)
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .image(let image):
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: contentWidth)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .table(let rows):
          ShareableTableView(rows: rows)
        }
      }

      Divider()
      HStack(spacing: 8) {
        Image(systemName: "graduationcap.fill")
          .foregroundStyle(.blue)
        VStack(alignment: .leading, spacing: 1) {
          Text("内蒙古高考")
            .font(.caption.weight(.semibold))
          Text("来源：内蒙古招生考试信息网")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
    }
    .padding(20)
    .frame(width: width, alignment: .leading)
    .background(Color(.systemBackground))
  }
}

/// 长图中的静态表格（不可滚动）。
private struct ShareableTableView: View {
  let rows: [[String]]

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
        HStack(spacing: 0) {
          ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
            Text(cell)
              .font(.caption2)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 6)
              .padding(.vertical, 5)
              .frame(maxWidth: .infinity, alignment: .leading)
              .overlay(
                Rectangle()
                  .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
              )
          }
        }
        .background(rowIndex == 0 ? Color.secondary.opacity(0.12) : Color.clear)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
    )
  }
}
