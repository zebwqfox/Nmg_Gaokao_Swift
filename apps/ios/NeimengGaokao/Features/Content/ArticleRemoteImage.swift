import SwiftUI
import UIKit

struct ArticleRemoteImage: View {
  let remoteURL: URL?
  let inlinePayload: String?
  let inlineData: Data?
  let caption: String
  var referer: URL?

  @State private var image: UIImage?
  @State private var failed = false

  init(url: URL, caption: String, referer: URL? = nil) {
    self.remoteURL = url
    self.inlinePayload = nil
    self.inlineData = nil
    self.caption = caption
    self.referer = referer
  }

  init(inlinePayload: String, caption: String) {
    self.remoteURL = nil
    self.inlinePayload = inlinePayload
    self.inlineData = nil
    self.caption = caption
    self.referer = nil
  }

  init(inlineData: Data, caption: String) {
    self.remoteURL = nil
    self.inlinePayload = nil
    self.inlineData = inlineData
    self.caption = caption
    self.referer = nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ZStack {
        if let image {
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
        } else if failed {
          ContentUnavailableView("图片加载失败", systemImage: "photo", description: Text(caption))
            .frame(maxWidth: .infinity, minHeight: 120)
            .transition(.opacity)
        } else {
          imagePlaceholder
            .transition(.opacity)
        }
      }
      .animation(.easeOut(duration: 0.28), value: image != nil)
      .animation(.easeOut(duration: 0.2), value: failed)

      if !caption.isEmpty, caption != remoteURL?.lastPathComponent {
        Text(caption)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .task(id: loadKey) {
      await load()
    }
  }

  private var imagePlaceholder: some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
      .fill(Color.secondary.opacity(0.10))
      .frame(maxWidth: .infinity, minHeight: 120)
      .overlay {
        VStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("图片加载中")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
  }

  private var loadKey: String {
    if let inlineData {
      return "data-\(inlineData.count)"
    }
    if let inlinePayload {
      return "inline-\(inlinePayload.count)"
    }
    return remoteURL?.absoluteString ?? "empty"
  }

  private func load() async {
    image = nil
    failed = false

    let loaded: UIImage?
    if let inlineData {
      loaded = await Task.detached(priority: .utility) {
        UIImage(data: inlineData)
      }.value
    } else if let inlinePayload {
      loaded = await Task.detached(priority: .utility) {
        Self.decodeInlineImage(inlinePayload)
      }.value
    } else if let remoteURL {
      loaded = await OfficialImageLoader.load(from: remoteURL, referer: referer)
    } else {
      loaded = nil
    }

    guard !Task.isCancelled else { return }

    if let loaded {
      withAnimation(.easeOut(duration: 0.28)) {
        image = loaded
      }
    } else {
      withAnimation(.easeOut(duration: 0.2)) {
        failed = true
      }
    }
  }

  nonisolated private static func decodeInlineImage(_ src: String) -> UIImage? {
    let trimmed = src.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if trimmed.lowercased().hasPrefix("data:") {
      return decodeDataURL(trimmed)
    }

    guard let data = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters) else {
      return nil
    }
    return UIImage(data: data)
  }

  nonisolated private static func decodeDataURL(_ src: String) -> UIImage? {
    guard let comma = src.firstIndex(of: ",") else { return nil }
    let metadata = src[..<comma].lowercased()
    let payload = String(src[src.index(after: comma)...])

    let data: Data?
    if metadata.contains("base64") {
      data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
    } else {
      data = payload.data(using: .utf8)
    }

    guard let data else { return nil }
    return UIImage(data: data)
  }
}
