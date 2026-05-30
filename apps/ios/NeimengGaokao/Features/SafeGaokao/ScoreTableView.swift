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

    // 学生门户子域（www4/www1）→ WebView，不要当列表页
    if host == "www4.nm.zsks.cn" || host == "www1.nm.zsks.cn" {
      return .web(title: article.title, url: url)
    }

    // www.nm.zsks.cn 目录/列表页（以 / 结尾或无扩展名）→ 原生列表
    if host == "www.nm.zsks.cn", path.hasSuffix("/") || !path.contains(".") {
      let category = OfficialCategory(
        id: article.id, title: article.title,
        kind: .notice, examType: nil, url: url
      )
      return .sectionList(category)
    }

    // 外站或 .jsp 交互页 → WebView
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
    .background(ClaudeTheme.surface.ignoresSafeArea())
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
              .font(.caption.weight(.semibold))
              .foregroundStyle(selectedKL == kl ? .white : ClaudeTheme.textSecondary)
              .padding(.horizontal, 14)
              .padding(.vertical, 7)
              .background(selectedKL == kl ? ClaudeTheme.primary : ClaudeTheme.surfaceCard)
              .overlay(
                Capsule().stroke(
                  selectedKL == kl ? ClaudeTheme.primary : ClaudeTheme.border,
                  lineWidth: 0.75
                )
              )
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
          .animation(.easeOut(duration: 0.15), value: selectedKL)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
    }
    .background(ClaudeTheme.surfaceCard)
  }

  // MARK: Content

  @ViewBuilder
  private var content: some View {
    if isLoading {
      VStack(spacing: 12) {
        ProgressView().tint(ClaudeTheme.primary)
        Text("正在加载数据")
          .font(.subheadline)
          .foregroundStyle(ClaudeTheme.textSecondary)
      }
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
      .foregroundStyle(ClaudeTheme.textTertiary)
      .padding(.horizontal, 12)
      .padding(.vertical, 5)
      .background(ClaudeTheme.surfaceCard)
      .overlay(Capsule().stroke(ClaudeTheme.border, lineWidth: 0.75))
      .clipShape(Capsule())
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
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 2) {
          let hasDistinctYXMC = (row.YXMC?.isEmpty == false) && row.YXMC != row.PCMC
          Text(hasDistinctYXMC ? row.YXMC! : row.PCMC)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ClaudeTheme.textPrimary)
            .lineLimit(2)
          if hasDistinctYXMC {
            Text(row.PCMC)
              .font(.caption)
              .foregroundStyle(ClaudeTheme.textTertiary)
              .lineLimit(1)
          }
        }
        Spacer()
        ScorePillView(min: row.ZDF, max: row.ZGF, count: row.TDRS, countLabel: "投档")
      }
      HStack(spacing: 8) {
        klChip(row.KLMC)
        if let yw = row.ZDF_YW { scoreChip("语", yw) }
        if let sx = row.ZDF_SX { scoreChip("数", sx) }
        if let wy = row.ZDF_WY { scoreChip("外", wy) }
      }
    }
    .padding(.vertical, 4)
  }

  private func scoreChip(_ label: String, _ value: String) -> some View {
    HStack(spacing: 2) {
      Text(label).foregroundStyle(ClaudeTheme.textTertiary)
      Text(value).foregroundStyle(ClaudeTheme.textPrimary)
    }
    .font(.caption.monospacedDigit())
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .background(ClaudeTheme.surface)
    .overlay(RoundedRectangle(cornerRadius: 4).stroke(ClaudeTheme.border, lineWidth: 0.75))
    .clipShape(RoundedRectangle(cornerRadius: 4))
  }

  private func klChip(_ kl: String) -> some View {
    Text(kl)
      .font(.caption2.weight(.medium))
      .foregroundStyle(ClaudeTheme.primary)
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(ClaudeTheme.primarySoft)
      .overlay(RoundedRectangle(cornerRadius: 4).stroke(ClaudeTheme.primary.opacity(0.25), lineWidth: 0.75))
      .clipShape(RoundedRectangle(cornerRadius: 4))
  }
}

private struct AdmissionScoreRowView: View {
  let row: AdmissionScoreRow

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 2) {
          Text(row.YXMC)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ClaudeTheme.textPrimary)
          if let zy = row.ZYMC, !zy.isEmpty {
            Text(zy)
              .font(.caption)
              .foregroundStyle(ClaudeTheme.textSecondary)
              .lineLimit(2)
          }
        }
        Spacer()
        ScorePillView(min: row.ZDF, max: row.ZGF, count: row.LQRS, countLabel: "录取")
      }
      HStack(spacing: 6) {
        Text(row.KLMC)
          .font(.caption2)
          .foregroundStyle(ClaudeTheme.success)
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
          .background(ClaudeTheme.success.opacity(0.08))
          .overlay(RoundedRectangle(cornerRadius: 4).stroke(ClaudeTheme.success.opacity(0.25), lineWidth: 0.75))
          .clipShape(RoundedRectangle(cornerRadius: 4))
        Text(row.PCMC)
          .font(.caption2)
          .foregroundStyle(ClaudeTheme.textSecondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
          .background(ClaudeTheme.surfaceCard)
          .overlay(RoundedRectangle(cornerRadius: 4).stroke(ClaudeTheme.border, lineWidth: 0.75))
          .clipShape(RoundedRectangle(cornerRadius: 4))
        if let jhl = row.JHLBMC, !jhl.isEmpty {
          Text(jhl)
            .font(.caption2)
            .foregroundStyle(ClaudeTheme.textTertiary)
        }
      }
    }
    .padding(.vertical, 4)
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
            .foregroundStyle(ClaudeTheme.primary)
        }
        if let maxS = max, !maxS.isEmpty {
          Text("~\(maxS)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(ClaudeTheme.textTertiary)
        }
      }
      if let c = count, !c.isEmpty {
        Text("\(c)\(countLabel)")
          .font(.caption2)
          .foregroundStyle(ClaudeTheme.textTertiary)
      }
    }
  }
}
