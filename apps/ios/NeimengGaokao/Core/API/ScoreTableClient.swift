import Foundation

// MARK: - Models

struct EnrollmentScoreRow: Identifiable, Decodable {
  let PCMC: String       // 批次名称
  let YXMC: String?      // 院校名称
  let KLMC: String       // 科类名称
  let ZGF: String?       // 最高分
  let ZDF: String?       // 最低分
  let TDRS: String?      // 投档人数
  let ZDF_YW: String?    // 语文
  let ZDF_SX: String?    // 数学
  let ZDF_WY: String?    // 外语
  let ZYZDH: String?     // 志愿顺序号
  let KLDM: String?

  var id: String { "\(PCMC)-\(KLDM ?? "")-\(ZYZDH ?? "")" }
  var minScore: Int? { Int(ZDF ?? "") }
  var maxScore: Int? { Int(ZGF ?? "") }
  var enrolled: Int? { Int(TDRS ?? "") }
}

struct AdmissionScoreRow: Identifiable, Decodable {
  let YXMC: String       // 院校名称
  let ZYMC: String?      // 专业名称
  let PCMC: String       // 批次名称
  let KLMC: String       // 科类名称
  let JHLBMC: String?    // 计划类别
  let ZGF: String?       // 最高分
  let ZDF: String?       // 最低分
  let LQRS: String?      // 录取人数
  let ZYZDH: String?
  let KLDM: String?
  let YXDH: String?

  var id: String { "\(YXMC)-\(ZYMC ?? "")-\(YXDH ?? "")-\(ZYZDH ?? "")" }
  var minScore: Int? { Int(ZDF ?? "") }
  var maxScore: Int? { Int(ZGF ?? "") }
  var admitted: Int? { Int(LQRS ?? "") }
}

// MARK: - Client

struct ScoreTableClient {
  var session: URLSession = OfficialSiteTrust.makeSession()

  /// 给定 tdzgzdf.html 或 lqzgzdf.html 的 URL，fetch 投档分数数据
  func fetchEnrollmentScores(pageURL: URL) async throws -> [EnrollmentScoreRow] {
    try await fetchJSON(from: dataURL(pageURL, file: "td.json"))
  }

  /// 给定 lqzgzdf.html 的 URL，fetch 录取分数数据
  func fetchAdmissionScores(pageURL: URL) async throws -> [AdmissionScoreRow] {
    try await fetchJSON(from: dataURL(pageURL, file: "lq.json"))
  }

  /// page: .../tj/tdzgzdf.html  →  data: .../data/td.json
  func dataURL(_ pageURL: URL, file: String) -> URL {
    pageURL
      .deletingLastPathComponent()          // remove filename
      .deletingLastPathComponent()          // remove "tj"
      .appendingPathComponent("data/\(file)")
  }

  private func fetchJSON<T: Decodable>(from url: URL) async throws -> [T] {
    var req = URLRequest(url: url)
    req.timeoutInterval = 25
    req.setValue("NeimengGaokaoApp/0.1", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await session.data(for: req)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw URLError(.badServerResponse)
    }
    return try JSONDecoder().decode([T].self, from: data)
  }
}
