import Foundation
import WebKit

enum OfficialWebSessionScript {
  static func makeUserScript(token: String?, baseUserInfoJSON: String? = nil) -> WKUserScript? {
    guard let source = injectionSource(token: token, baseUserInfoJSON: baseUserInfoJSON) else {
      return nil
    }
    return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
  }

  static func injectionSource(token: String?, baseUserInfoJSON: String? = nil) -> String? {
    guard let token, !token.isEmpty else { return nil }
    let userInfoObject = baseUserInfoJSON.flatMap(jsonObject) ?? ["token": token]
    guard let tokenValue = try? encryptedStorageValue(token),
          let userInfoValue = try? encryptedStorageValue(userInfoObject)
    else {
      return nil
    }

    return """
    (function() {
      try {
        sessionStorage.setItem("STUTOKEN", \(jsString(tokenValue)));
        sessionStorage.setItem("BASEUSERINFO", \(jsString(userInfoValue)));
        localStorage.setItem("STUTOKEN", \(jsString(tokenValue)));
        localStorage.setItem("BASEUSERINFO", \(jsString(userInfoValue)));
        window.__NEIMENG_GAOKAO_APP_SESSION__ = true;
      } catch (error) {
        console.warn("Failed to inject official session", error);
      }
    })();
    """
  }

  private static func encryptedStorageValue(_ value: Any, ttl: TimeInterval = 86_400) throws -> String {
    let now = Date()
    let envelope: [String: Any] = [
      "value": value,
      "time": ISO8601DateFormatter().string(from: now),
      "expire": Int((now.timeIntervalSince1970 + ttl) * 1000)
    ]
    let data = try JSONSerialization.data(withJSONObject: envelope, options: [])
    guard let json = String(data: data, encoding: .utf8) else {
      throw SessionScriptError.invalidJSON
    }
    return try OfficialPasswordCipher.encrypt(json)
  }

  private static func jsString(_ value: String) -> String {
    guard let data = try? JSONEncoder().encode(value),
          let encoded = String(data: data, encoding: .utf8)
    else {
      return "\"\""
    }
    return encoded
  }

  private static func jsonObject(from string: String) -> Any? {
    guard let data = string.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
  }

  private enum SessionScriptError: Error {
    case invalidJSON
  }
}
