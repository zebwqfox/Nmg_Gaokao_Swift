import Foundation

enum OfficialURLFallback {
  static func candidateURLs(for url: URL) -> [URL] {
    guard let scheme = url.scheme?.lowercased(),
          let host = url.host?.lowercased(),
          host.contains("nm.zsks.cn")
    else {
      return [url]
    }

    if scheme == "https", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
      components.scheme = "http"
      if let fallback = components.url {
        return [url, fallback]
      }
    } else if scheme == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
      components.scheme = "https"
      if let fallback = components.url {
        return [url, fallback]
      }
    }

    return [url]
  }

  static func alternateURL(for url: URL, excluding: Set<String> = []) -> URL? {
    candidateURLs(for: url).first { candidate in
      !excluding.contains(candidate.absoluteString)
    }
  }
}
