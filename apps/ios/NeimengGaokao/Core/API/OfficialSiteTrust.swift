import Foundation

/// 官方站点证书偶发过期时，仍允许 App 继续访问（仅限 `nm.zsks.cn` 域名）。
enum OfficialSiteTrust {
  static func isOfficialHost(_ host: String) -> Bool {
    host.lowercased().contains("nm.zsks.cn")
  }

  static func accept(
    challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
          let trust = challenge.protectionSpace.serverTrust,
          isOfficialHost(challenge.protectionSpace.host)
    else {
      completionHandler(.performDefaultHandling, nil)
      return
    }
    completionHandler(.useCredential, URLCredential(trust: trust))
  }

  static func makeSession(configuration: URLSessionConfiguration = .default) -> URLSession {
    let config = configuration
    config.timeoutIntervalForRequest = 25
    config.timeoutIntervalForResource = 45
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.urlCache = nil
    return URLSession(configuration: config, delegate: SessionDelegate(), delegateQueue: nil)
  }

  /// 独立创建一个 SSL 信任代理，供外部 session 复用
  static func makeSessionDelegate() -> URLSessionDelegate {
    SessionDelegate()
  }

  private final class SessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
      _ session: URLSession,
      didReceive challenge: URLAuthenticationChallenge,
      completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
      OfficialSiteTrust.accept(challenge: challenge, completionHandler: completionHandler)
    }
  }
}
