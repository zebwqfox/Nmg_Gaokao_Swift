import SwiftUI
import UIKit

struct ArticleRemoteImage: View {
  let url: URL
  let caption: String

  @State private var image: UIImage?
  @State private var failed = false

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
      if !caption.isEmpty, caption != url.lastPathComponent {
        Text(caption)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .task(id: url) {
      await load()
    }
  }

  private func load() async {
    image = nil
    failed = false
    do {
      let (data, response) = try await OfficialSiteTrust.makeSession().data(from: url)
      guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
            let loaded = UIImage(data: data)
      else {
        failed = true
        return
      }
      image = loaded
    } catch {
      failed = true
    }
  }
}
