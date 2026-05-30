import Foundation

// MARK: - Raw decodable rows

private struct EnrollmentScoreRow: Decodable {
  let PCMC: String       // 批次名称
  let YXMC: String?      // 院校名称
  let KLMC: String       // 科类名称
  let ZGF: String?       // 最高分
  let ZDF: String?       // 最低分
  let TDRS: String?      // 投档人数
  let ZDF_YW: String?    // 语文
  let ZDF_SX: String?    // 数学
  let ZDF_WY: String?    // 外语
  let ZYZDH: String?     // 志愿/专业组顺序号
  let KLDM: String?
}

private struct AdmissionScoreRow: Decodable {
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
  let YXDH: String?      // 院校代号
}

// MARK: - Normalized models

struct SubjectScore: Identifiable {
  let id = UUID()
  let label: String
  let value: String
}

/// 一条分数明细（一个专业，或一个专业组志愿）
struct ScoreItem: Identifiable {
  let id: String
  let school: String         // 院校名 YXMC（投档表用批次聚合名）
  let title: String          // 专业名 或 "专业组 003"
  let subtitle: String?      // 批次 / 计划类别
  let category: String       // 科类名 KLMC
  let minScore: Int?
  let maxScore: Int?
  let peopleCount: Int?      // 录取 / 投档人数
  let subjectScores: [SubjectScore]  // 语数外（仅投档有）
}

/// 一所院校的分组聚合
struct SchoolScoreGroup: Identifiable {
  let id: String
  let school: String
  let items: [ScoreItem]

  var minScore: Int? { items.compactMap(\.minScore).min() }
  var maxScore: Int? { items.compactMap(\.maxScore).max() }
  var totalPeople: Int { items.compactMap(\.peopleCount).reduce(0, +) }
  var itemCount: Int { items.count }
}

// MARK: - Client

struct ScoreTableClient {
  var session: URLSession = OfficialSiteTrust.makeSession()

  /// 投档分数（td.json）→ 归一化明细
  func fetchEnrollmentItems(pageURL: URL) async throws -> [ScoreItem] {
    let rows: [EnrollmentScoreRow] = try await fetchJSON(from: dataURL(pageURL, file: "td.json"))
    return rows.enumerated().map { idx, r in
      var subjects: [SubjectScore] = []
      if let v = r.ZDF_YW, !v.isEmpty { subjects.append(SubjectScore(label: "语", value: v)) }
      if let v = r.ZDF_SX, !v.isEmpty { subjects.append(SubjectScore(label: "数", value: v)) }
      if let v = r.ZDF_WY, !v.isEmpty { subjects.append(SubjectScore(label: "外", value: v)) }
      // 投档表无专业名，用志愿组号
      let groupLabel = (r.ZYZDH?.isEmpty == false) ? "专业组 \(r.ZYZDH!)" : "投档"
      return ScoreItem(
        id: "td-\(idx)",
        school: r.YXMC ?? r.PCMC,
        title: groupLabel,
        subtitle: r.PCMC,
        category: r.KLMC,
        minScore: Int(r.ZDF ?? ""),
        maxScore: Int(r.ZGF ?? ""),
        peopleCount: Int(r.TDRS ?? ""),
        subjectScores: subjects
      )
    }
  }

  /// 录取分数（lq.json）→ 归一化明细
  func fetchAdmissionItems(pageURL: URL) async throws -> [ScoreItem] {
    let rows: [AdmissionScoreRow] = try await fetchJSON(from: dataURL(pageURL, file: "lq.json"))
    return rows.enumerated().map { idx, r in
      let major = (r.ZYMC?.isEmpty == false) ? r.ZYMC! : "（未注明专业）"
      var sub = r.PCMC
      if let jhl = r.JHLBMC, !jhl.isEmpty, jhl != "普通类" {
        sub += " · \(jhl)"
      }
      return ScoreItem(
        id: "lq-\(idx)",
        school: r.YXMC,
        title: major,
        subtitle: sub,
        category: r.KLMC,
        minScore: Int(r.ZDF ?? ""),
        maxScore: Int(r.ZGF ?? ""),
        peopleCount: Int(r.LQRS ?? ""),
        subjectScores: []
      )
    }
  }

  /// page: .../tj/tdzgzdf.html  →  data: .../data/td.json
  func dataURL(_ pageURL: URL, file: String) -> URL {
    pageURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
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

// MARK: - Grouping helpers

enum ScoreGrouping {
  /// 提取科类列表（保持出现顺序），用于过滤 chip
  static func categories(from items: [ScoreItem]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for item in items where seen.insert(item.category).inserted {
      result.append(item.category)
    }
    return result
  }

  /// 按科类过滤 + 关键词搜索 + 按院校分组，组内按最低分降序，组间按最低分降序
  static func groups(
    from items: [ScoreItem],
    category: String,
    query: String
  ) -> [SchoolScoreGroup] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    var buckets: [String: [ScoreItem]] = [:]
    var order: [String] = []

    for item in items {
      if category != "全部", item.category != category { continue }
      let school = item.school
      let schoolMatches = trimmed.isEmpty || school.localizedCaseInsensitiveContains(trimmed)
      let itemMatches = trimmed.isEmpty || item.title.localizedCaseInsensitiveContains(trimmed)
      // 院校名命中 → 保留全部专业；否则仅保留命中专业
      guard schoolMatches || itemMatches else { continue }
      if buckets[school] == nil { order.append(school) }
      buckets[school, default: []].append(item)
    }

    var result = order.map { school -> SchoolScoreGroup in
      let sorted = buckets[school]!.sorted { ($0.minScore ?? -1) > ($1.minScore ?? -1) }
      return SchoolScoreGroup(id: school, school: school, items: sorted)
    }
    result.sort { ($0.minScore ?? -1) > ($1.minScore ?? -1) }
    return result
  }
}
