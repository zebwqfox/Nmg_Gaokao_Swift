import SwiftUI

// MARK: - Route helper

extension AppRoute {
  /// 根据文章 URL 自动路由：
  /// - tdzgzdf.html / lqzgzdf.html → 原生分数表格
  /// - nm.zsks.cn 目录/列表页      → 原生分页列表
  /// - 外站或 .jsp 交互页          → WebView
  /// - 其他文章页                  → ArticleDetailView
  static func smart(for article: CachedArticle) -> AppRoute {
    let url = article.originalURL
    let path = url.path
    let host = url.host?.lowercased() ?? ""

    // 精确匹配分数表格页（必须以 .html 结尾，避免误匹配目录名）
    if path.hasSuffix("tdzgzdf.html") {
      return .scoreTable(title: article.title, pageURL: url, isAdmission: false)
    }
    if path.hasSuffix("lqzgzdf.html") {
      return .scoreTable(title: article.title, pageURL: url, isAdmission: true)
    }

    // nm.zsks.cn 目录/列表页（以 / 结尾或无扩展名）→ 原生列表
    if host.contains("nm.zsks.cn"), path.hasSuffix("/") || !path.contains(".") {
      let category = OfficialCategory(
        id: article.id, title: article.title,
        kind: .notice, examType: nil, url: url
      )
      return .sectionList(category)
    }

    // 外站 URL 或 .jsp 交互页（如录取查询）→ WebView
    if !host.contains("nm.zsks.cn") || path.hasSuffix(".jsp") {
      return .web(title: article.title, url: url)
    }

    return .article(id: article.id)
  }
}

// MARK: - ScoreTableView

struct ScoreTableView: View {
  let title: String
  let pageURL: URL
  let isAdmission: Bool

  @State private var enrollmentRows: [EnrollmentScoreRow] = []
  @State private var admissionRows: [AdmissionScoreRow] = []
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var searchText = ""
  @State private var selectedKL = "全部"

  private let client = ScoreTableClient()

  private var subjectCategories: [String] {
    var seen = Set<String>()
    var result = ["全部"]
    let allKL = isAdmission
      ? admissionRows.map(\.KLMC)
      : enrollmentRows.map(\.KLMC)
    for kl in allKL where seen.insert(kl).inserted {
      result.append(kl)
    }
    return result
  }

  var body: some View {
    VStack(spacing: 0) {
      filterBar
      Divider()
      content
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $searchText, prompt: isAdmission ? "搜索院校或专业" : "搜索批次或院校")
    .task { await load() }
  }

  // MARK: Filter bar

  private var filterBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(subjectCategories, id: \.self) { kl in
          Button {
            selectedKL = kl
          } label: {
            Text(kl)
              .font(.subheadline.weight(.semibold))
              .padding(.horizontal, 14)
              .padding(.vertical, 7)
          }
          .buttonStyle(.plain)
          .foregroundStyle(selectedKL == kl ? .white : .primary)
          .glassEffect(
            selectedKL == kl
              ? .regular.tint(.blue.opacity(0.3)).interactive()
              : .regular.interactive(),
            in: .rect(cornerRadius: 999)
          )
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
    }
  }

  // MARK: Content

  @ViewBuilder
  private var content: some View {
    if isLoading {
      ProgressView("正在加载数据")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let error = errorMessage {
      ContentUnavailableView(
        "加载失败",
        systemImage: "wifi.exclamationmark",
        description: Text(error)
      )
    } else if isAdmission {
      admissionList
    } else {
      enrollmentList
    }
  }

  // MARK: Enrollment list (投档)

  private var filteredEnrollment: [EnrollmentScoreRow] {
    enrollmentRows
      .filter { row in
        (selectedKL == "全部" || row.KLMC == selectedKL)
        && (searchText.isEmpty
          || (row.PCMC.localizedCaseInsensitiveContains(searchText))
          || (row.YXMC?.localizedCaseInsensitiveContains(searchText) == true))
      }
      .sorted { ($0.minScore ?? 0) > ($1.minScore ?? 0) }
  }

  private var enrollmentList: some View {
    Group {
      if filteredEnrollment.isEmpty {
        ContentUnavailableView("无匹配结果", systemImage: "doc.text.magnifyingglass")
      } else {
        List(filteredEnrollment) { row in
          EnrollmentScoreRowView(row: row)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        }
        .listStyle(.plain)
        .overlay(alignment: .bottom) {
          countBadge(filteredEnrollment.count)
        }
      }
    }
  }

  // MARK: Admission list (录取)

  private var filteredAdmission: [AdmissionScoreRow] {
    admissionRows
      .filter { row in
        (selectedKL == "全部" || row.KLMC == selectedKL)
        && (searchText.isEmpty
          || row.YXMC.localizedCaseInsensitiveContains(searchText)
          || (row.ZYMC?.localizedCaseInsensitiveContains(searchText) == true)
          || row.PCMC.localizedCaseInsensitiveContains(searchText))
      }
      .sorted { ($0.minScore ?? 0) > ($1.minScore ?? 0) }
  }

  private var admissionList: some View {
    Group {
      if filteredAdmission.isEmpty {
        ContentUnavailableView("无匹配结果", systemImage: "doc.text.magnifyingglass")
      } else {
        List(filteredAdmission) { row in
          AdmissionScoreRowView(row: row)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        }
        .listStyle(.plain)
        .overlay(alignment: .bottom) {
          countBadge(filteredAdmission.count)
        }
      }
    }
  }

  private func countBadge(_ count: Int) -> some View {
    Text("\(count) 条")
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 12)
      .padding(.vertical, 5)
      .nativeGlassPanel(cornerRadius: 999)
      .padding(.bottom, 12)
  }

  // MARK: Load

  private func load() async {
    guard !isLoading else { return }
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      if isAdmission {
        admissionRows = try await client.fetchAdmissionScores(pageURL: pageURL)
      } else {
        enrollmentRows = try await client.fetchEnrollmentScores(pageURL: pageURL)
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

// MARK: - Row views

private struct EnrollmentScoreRowView: View {
  let row: EnrollmentScoreRow

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 2) {
          Text(row.PCMC)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(2)
          if let yxmc = row.YXMC, !yxmc.isEmpty, yxmc != row.PCMC {
            Text(yxmc)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        ScorePillView(min: row.ZDF, max: row.ZGF, count: row.TDRS, countLabel: "投档")
      }
      if row.ZDF_YW != nil || row.ZDF_SX != nil || row.ZDF_WY != nil {
        HStack(spacing: 10) {
          Text(row.KLMC)
            .font(.caption2)
            .foregroundStyle(.blue)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .nativeGlassPanel(cornerRadius: 4, tint: .blue.opacity(0.1))
          if let yw = row.ZDF_YW { scoreTag("语", yw) }
          if let sx = row.ZDF_SX { scoreTag("数", sx) }
          if let wy = row.ZDF_WY { scoreTag("外", wy) }
        }
      } else {
        klTag(row.KLMC)
      }
    }
  }

  private func scoreTag(_ label: String, _ value: String) -> some View {
    HStack(spacing: 2) {
      Text(label).foregroundStyle(.secondary)
      Text(value).foregroundStyle(.primary)
    }
    .font(.caption.monospacedDigit())
  }

  private func klTag(_ kl: String) -> some View {
    Text(kl)
      .font(.caption2)
      .foregroundStyle(.blue)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .nativeGlassPanel(cornerRadius: 4, tint: .blue.opacity(0.1))
  }
}

private struct AdmissionScoreRowView: View {
  let row: AdmissionScoreRow

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 2) {
          Text(row.YXMC)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
          if let zy = row.ZYMC, !zy.isEmpty {
            Text(zy)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
        }
        Spacer()
        ScorePillView(min: row.ZDF, max: row.ZGF, count: row.LQRS, countLabel: "录取")
      }
      HStack(spacing: 6) {
        Text(row.KLMC)
          .font(.caption2)
          .foregroundStyle(.green)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .nativeGlassPanel(cornerRadius: 4, tint: .green.opacity(0.1))
        Text(row.PCMC)
          .font(.caption2)
          .foregroundStyle(.orange)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .nativeGlassPanel(cornerRadius: 4, tint: .orange.opacity(0.1))
        if let jhl = row.JHLBMC, !jhl.isEmpty {
          Text(jhl)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

private struct ScorePillView: View {
  let min: String?
  let max: String?
  let count: String?
  let countLabel: String

  var body: some View {
    VStack(alignment: .trailing, spacing: 2) {
      HStack(spacing: 4) {
        if let minS = min, !minS.isEmpty {
          Text(minS)
            .font(.title3.weight(.bold).monospacedDigit())
            .foregroundStyle(.red)
        }
        if let maxS = max, !maxS.isEmpty {
          Text("~\(maxS)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
      if let c = count, !c.isEmpty {
        Text("\(c)\(countLabel)")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
    }
  }
}
