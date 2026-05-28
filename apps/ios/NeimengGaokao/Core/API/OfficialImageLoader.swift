import Foundation
import UIKit

enum OfficialImageLoader {
  static func load(from url: URL, referer: URL? = nil) async -> UIImage? {
    let refererURL = referer ?? URL(string: "https://www.nm.zsks.cn/")!

    for candidate in OfficialURLFallback.candidateURLs(for: url) {
      if let image = try? await fetch(candidate, referer: refererURL) {
        return image
      }
    }
    return nil
  }

  private static func fetch(_ url: URL, referer: URL) async throws -> UIImage {
    var request = URLRequest(url: url)
    request.timeoutInterval = 25
    request.setValue("NeimengGaokaoApp/0.1", forHTTPHeaderField: "User-Agent")
    request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
    request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

    let (data, response) = try await OfficialSiteTrust.makeSession().data(for: request)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw URLError(.badServerResponse)
    }
    guard let image = UIImage(data: data) else {
      throw URLError(.cannotDecodeContentData)
    }
    return image
  }
}
