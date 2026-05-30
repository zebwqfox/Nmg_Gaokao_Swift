import SwiftUI

// MARK: - Route helper

extension AppRoute {
  /// 根据文章 URL 自动路由
  static func smart(for article: CachedArticle) -> AppRoute {
    let url = article.originalURL
    let path = url.path
    let host = url.host?.lowercased() ?? ""

    if path.hasSuffix("tdzgzdf.html") {
      return .scoreTable(title: article.title, pageURL: url, isAdmission: false)
    }
    if path.hasSuffix("lqzgzdf.html") {
      return .scoreTable(title: article.title, pageURL: url, isAdmission: true)
    }
    if host == "www4.nm.zsks.cn" || host == "www1.nm.zsks.cn" {
      return .web(title: article.title, url: url)
    }
    if host == "www.nm.zsks.cn", path.hasSuffix("/") || !path.contains(".") {
      let category = OfficialCategory(
        id: article.id, title: article.title,
        kind: .notice, examType: nil, url: url
      )
      return .sectionList(category)
    }
    if !host.contains("nm.zsks.cn") || path.hasSuffix(".jsp") {
      return .web(title: article.title, url: url)
    }
    return .article(id: article.id)
  }
}

// MARK: - ScoreTableView (院校列表)

struct ScoreTableView: View {
  let title: String
  let pageURL: URL
  let isAdmission: Bool

  @State private var items: [ScoreItem] = []
  @State private var categories: [String] = ["全部"]
  @State private var groups: [SchoolScoreGroup] = []
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var searchText = ""
  @State private var selectedCategory = "全部"

  private let client = ScoreTableClient()

  var body: some View {
    VStack(spacing: 0) {
      if !isLoading, errorMessage == nil, !items.isEmpty {
        categoryBar
        Divider()
      }
      content
    }
    .background(ClaudeTheme.surface.ignoresSafeArea())
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索院校或专业")
    .task { await load() }
    .onChange(of: searchText) { recomputeGroups() }
    .onChange(of: selectedCategory) { recomputeGroups() }
  }

  private func recomputeGroups() {
    groups = ScoreGrouping.groups(from: items, category: selectedCategory, query: searchText)
  }

  // MARK: Category filter

  private var categoryBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(categories, id: \.self) { cat in
          let selected = selectedCategory == cat
          Button {
            selectedCategory = cat
          } label: {
            Text(cat)
              .font(.caption.weight(.semibold))
              .foregroundStyle(selected ? .white : ClaudeTheme.textSecondary)
              .padding(.horizontal, 14)
              .padding(.vertical, 7)
              .background(selected ? ClaudeTheme.primary : ClaudeTheme.surfaceCard)
              .overlay(
                Capsule().stroke(selected ? ClaudeTheme.primary : ClaudeTheme.border, lineWidth: 0.75)
              )
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
          .animation(.easeOut(duration: 0.15), value: selectedCategory)
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
        Text("正在加载分数数据")
          .font(.subheadline)
          .foregroundStyle(ClaudeTheme.textSecondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let error = errorMessage {
      ContentUnavailableView("加载失败", systemImage: "wifi.exclamationmark", description: Text(error))
    } else if groups.isEmpty {
      ContentUnavailableView(
        searchText.isEmpty ? "暂无数据" : "无匹配结果",
        systemImage: "doc.text.magnifyingglass"
      )
    } else {
      schoolList
    }
  }

  private var schoolList: some View {
    ScrollView {
      LazyVStack(spacing: 10) {
        // 顶部统计
        HStack {
          Text("共 \(groups.count) 所院校")
            .font(.caption.weight(.medium))
            .foregroundStyle(ClaudeTheme.textTertiary)
          Spacer()
          Text(isAdmission ? "录取分数线" : "投档分数线")
            .font(.caption)
            .foregroundStyle(ClaudeTheme.textTertiary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)

        ForEach(groups) { group in
          NavigationLink {
            ScoreSchoolDetailView(group: group, isAdmission: isAdmission)
          } label: {
            SchoolGroupRow(group: group, isAdmission: isAdmission)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(16)
    }
  }

  // MARK: Load

  private func load() async {
    guard !isLoading, items.isEmpty else { return }
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      let loaded = isAdmission
        ? try await client.fetchAdmissionItems(pageURL: pageURL)
        : try await client.fetchEnrollmentItems(pageURL: pageURL)
      items = loaded
      categories = ["全部"] + ScoreGrouping.categories(from: loaded)
      recomputeGroups()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

// MARK: - School group row

private struct SchoolGroupRow: View {
  let group: SchoolScoreGroup
  let isAdmission: Bool

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 5) {
        Text(group.school)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(ClaudeTheme.textPrimary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
        HStack(spacing: 8) {
          metaChip(icon: "list.bullet", text: isAdmission ? "\(group.itemCount)个专业" : "\(group.itemCount)个专业组")
          if group.totalPeople > 0 {
            metaChip(icon: "person.2", text: "\(group.totalPeople)人")
          }
        }
      }
      Spacer(minLength: 8)

      // 分数区间
      VStack(alignment: .trailing, spacing: 1) {
        if let min = group.minScore {
          Text("\(min)")
            .font(.title3.weight(.bold).monospacedDigit())
            .foregroundStyle(ClaudeTheme.primary)
          Text("最低分")
            .font(.caption2)
            .foregroundStyle(ClaudeTheme.textTertiary)
        }
      }
      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundStyle(ClaudeTheme.textTertiary)
    }
    .padding(14)
    .background(ClaudeTheme.surfaceCard)
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(ClaudeTheme.border, lineWidth: 0.75)
    )
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private func metaChip(icon: String, text: String) -> some View {
    HStack(spacing: 3) {
      Image(systemName: icon).font(.caption2)
      Text(text).font(.caption2)
    }
    .foregroundStyle(ClaudeTheme.textTertiary)
  }
}

// MARK: - School detail (专业列表)

struct ScoreSchoolDetailView: View {
  let group: SchoolScoreGroup
  let isAdmission: Bool

  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        summaryCard
        ForEach(group.items) { item in
          ScoreItemRow(item: item, isAdmission: isAdmission)
        }
      }
      .padding(16)
    }
    .background(ClaudeTheme.surface.ignoresSafeArea())
    .navigationTitle(group.school)
    .navigationBarTitleDisplayMode(.inline)
  }

  private var summaryCard: some View {
    HStack(spacing: 0) {
      summaryStat(value: group.minScore.map(String.init) ?? "—", label: "最低分", accent: ClaudeTheme.primary)
      divider
      summaryStat(value: group.maxScore.map(String.init) ?? "—", label: "最高分", accent: ClaudeTheme.info)
      divider
      summaryStat(value: "\(group.itemCount)", label: isAdmission ? "专业" : "专业组", accent: ClaudeTheme.textSecondary)
      if group.totalPeople > 0 {
        divider
        summaryStat(value: "\(group.totalPeople)", label: "人数", accent: ClaudeTheme.success)
      }
    }
    .padding(.vertical, 16)
    .frame(maxWidth: .infinity)
    .background(ClaudeTheme.surfaceCard)
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(ClaudeTheme.border, lineWidth: 0.75)
    )
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private func summaryStat(value: String, label: String, accent: Color) -> some View {
    VStack(spacing: 3) {
      Text(value)
        .font(.title3.weight(.bold).monospacedDigit())
        .foregroundStyle(accent)
      Text(label)
        .font(.caption2)
        .foregroundStyle(ClaudeTheme.textTertiary)
    }
    .frame(maxWidth: .infinity)
  }

  private var divider: some View {
    Rectangle()
      .fill(ClaudeTheme.border)
      .frame(width: 0.75, height: 28)
  }
}

// MARK: - Score item row

private struct ScoreItemRow: View {
  let item: ScoreItem
  let isAdmission: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(item.title)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(ClaudeTheme.textPrimary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
        if let sub = item.subtitle, !sub.isEmpty {
          Text(sub)
            .font(.caption)
            .foregroundStyle(ClaudeTheme.textTertiary)
            .lineLimit(1)
        }
        if !item.subjectScores.isEmpty {
          HStack(spacing: 6) {
            ForEach(item.subjectScores) { s in
              HStack(spacing: 2) {
                Text(s.label).foregroundStyle(ClaudeTheme.textTertiary)
                Text(s.value).foregroundStyle(ClaudeTheme.textSecondary)
              }
              .font(.caption2.monospacedDigit())
            }
          }
        }
      }
      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 1) {
        HStack(spacing: 4) {
          if let min = item.minScore {
            Text("\(min)")
              .font(.headline.monospacedDigit())
              .foregroundStyle(ClaudeTheme.primary)
          }
          if let max = item.maxScore {
            Text("~\(max)")
              .font(.caption.monospacedDigit())
              .foregroundStyle(ClaudeTheme.textTertiary)
          }
        }
        if let count = item.peopleCount {
          Text("\(count)\(isAdmission ? "录取" : "投档")")
            .font(.caption2)
            .foregroundStyle(ClaudeTheme.textTertiary)
        }
      }
    }
    .padding(14)
    .background(ClaudeTheme.surfaceCard)
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(ClaudeTheme.border, lineWidth: 0.75)
    )
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}
