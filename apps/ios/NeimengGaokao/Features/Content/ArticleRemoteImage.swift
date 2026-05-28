import SwiftUI
import UIKit

struct ArticleRemoteImage: View {
  let remoteURL: URL?
  let inlineData: Data?
  let caption: String
  var referer: URL?

  @State private var image: UIImage?
  @State private var failed = false

  init(url: URL, caption: String, referer: URL? = nil) {
    self.remoteURL = url
    self.inlineData = nil
    self.caption = caption
    self.referer = referer
  }

  init(inlineData: Data, caption: String) {
    self.remoteURL = nil
    self.inlineData = inlineData
    self.caption = caption
    self.referer = nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Group {
        if let image {
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else if failed {
          ContentUnavailableView("图片加载失败", systemImage: "photo", description: Text(caption))
            .frame(maxWidth: .infinity, minHeight: 120)
        } else {
          ProgressView()
            .frame(maxWidth: .infinity, minHeight: 120)
        }
      }
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

  private var loadKey: String {
    if let inlineData {
      return "inline-\(inlineData.count)"
    }
    return remoteURL?.absoluteString ?? "empty"
  }

  private func load() async {
    image = nil
    failed = false

    if let inlineData, let loaded = UIImage(data: inlineData) {
      image = loaded
      return
    }

    guard let remoteURL else {
      failed = true
      return
    }

    if let loaded = await OfficialImageLoader.load(from: remoteURL, referer: referer) {
      image = loaded
    } else {
      failed = true
    }
  }
}
