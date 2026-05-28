import Foundation

struct OfficialStudentClient {
  var session: URLSession = .shared
  let baseURL = URL(string: "https://www4.nm.zsks.cn/exam/basic-student/api/")!

  func login(idNumber: String, password: String, captcha: String) async throws -> OfficialLoginResponse {
    let encryptedPassword = try OfficialPasswordCipher.encrypt(password)
    let url = baseURL.appending(path: "student/login")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode([
      "username": idNumber.uppercased(),
      "password": encryptedPassword,
      "code": captcha
    ])
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, 200..<500 ~= http.statusCode else {
      throw URLError(.badServerResponse)
    }
    return try JSONDecoder().decode(OfficialLoginResponse.self, from: data)
  }

  func fetchExamTypes(token: String? = nil) async throws -> OfficialEnvelope<[OfficialExamType]> {
    var request = URLRequest(url: baseURL.appending(path: "stusercenter/getExamTypeList"))
    apply(token: token, to: &request)
    let (data, _) = try await session.data(for: request)
    return try JSONDecoder().decode(OfficialEnvelope<[OfficialExamType]>.self, from: data)
  }

  func fetchExamCalendar(token: String? = nil) async throws -> OfficialEnvelope<[OfficialCalendarItem]> {
    var request = URLRequest(url: baseURL.appending(path: "stusercenter/getExamCalendarV2"))
    apply(token: token, to: &request)
    let (data, _) = try await session.data(for: request)
    return try JSONDecoder().decode(OfficialEnvelope<[OfficialCalendarItem]>.self, from: data)
  }

  func fetchStudentServices(token: String? = nil) async throws -> OfficialEnvelope<[OfficialStudentService]> {
    var request = URLRequest(url: baseURL.appending(path: "stusercenter/serlist"))
    apply(token: token, to: &request)
    let (data, _) = try await session.data(for: request)
    return try JSONDecoder().decode(OfficialEnvelope<[OfficialStudentService]>.self, from: data)
  }

  func makeCaptcha(length: Int = 4) -> String {
    let alphabet = Array("ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz23456789")
    return String((0..<length).compactMap { _ in alphabet.randomElement() })
  }

  private func apply(token: String?, to request: inout URLRequest) {
    if let token, !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
  }
}

struct OfficialLoginResponse: Decodable {
  let code: Int
  let success: Bool?
  let message: String?
  let data: OfficialLoginData?

  var displayMessage: String {
    message ?? (code == 200 ? "登录成功" : "官方接口未返回错误原因")
  }
}

struct OfficialLoginData: Decodable {
  let token: String?
  let raw: JSONValue

  enum CodingKeys: String, CodingKey {
    case token
  }

  init(from decoder: Decoder) throws {
    raw = try JSONValue(from: decoder)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    token = try container.decodeIfPresent(String.self, forKey: .token)
  }

  var storageJSONString: String? {
    raw.jsonString
  }
}

struct OfficialEnvelope<T: Decodable>: Decodable {
  let code: Int
  let success: Bool?
  let message: String?
  let data: T?
}

struct OfficialExamType: Decodable, Identifiable, Hashable {
  var id: String { kslxdm }
  let kslxdm: String
  let kslxmc: String
  let syzt: String?
  let phoneFlag: String?
}

struct OfficialCalendarItem: Decodable, Identifiable, Hashable {
  var id: String { "\(title ?? "")-\(startTime ?? "")-\(endTime ?? "")" }
  let title: String?
  let startTime: String?
  let endTime: String?
  let content: String?
  let kslxdm: String?
  let kslxmc: String?

  enum CodingKeys: String, CodingKey {
    case title
    case startTime
    case endTime
    case content
    case kslxdm
    case kslxmc
  }
}

struct OfficialStudentService: Decodable, Identifiable, Hashable {
  var id: String { "\(name ?? "")-\(planCode ?? "")-\(url ?? "")" }
  let name: String?
  let type: String?
  let url: String?
  let planCode: String?
  let src: String?
  let outFlag: String?
  let examTypeCode: String?
  let scheCode: String?

  func launchURL(token: String?) -> URL {
    if outFlag == "1", let url = url, let externalURL = URL(string: url) {
      return externalURL.appendingOfficialQuery(planCode: planCode, token: token)
    }

    let resolvedSource = src ?? url?.officialFragmentSource
    if let resolvedSource, !resolvedSource.isEmpty {
      var components = URLComponents(string: "https://www4.nm.zsks.cn/BaseStudent/systemTotal")!
      components.queryItems = [
        URLQueryItem(name: "src", value: resolvedSource),
        URLQueryItem(name: "planCode", value: planCode)
      ]
      return components.url ?? OfficialServiceCatalog.studentPortal
    }

    return OfficialServiceCatalog.studentPortal
  }
}

private extension String {
  var officialFragmentSource: String? {
    guard let hashIndex = firstIndex(of: "#") else { return nil }
    let source = self[index(after: hashIndex)...]
    return source.isEmpty ? nil : String(source)
  }
}

private extension URL {
  func appendingOfficialQuery(planCode: String?, token: String?) -> URL {
    guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
      return self
    }
    var items = components.queryItems ?? []
    if let planCode, !planCode.isEmpty, !items.contains(where: { $0.name == "planCode" }) {
      items.append(URLQueryItem(name: "planCode", value: planCode))
    }
    if let token, !token.isEmpty, !items.contains(where: { $0.name == "token" }) {
      items.append(URLQueryItem(name: "token", value: token))
    }
    components.queryItems = items
    return components.url ?? self
  }
}
