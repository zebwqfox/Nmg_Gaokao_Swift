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
    return URLSession(configuration: config, delegate: SessionDelegate(), delegateQueue: nil)
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
