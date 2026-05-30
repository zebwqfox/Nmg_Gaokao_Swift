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
      }
      content
    }
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
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(selected ? .white : .primary)
              .padding(.horizontal, 14)
              .padding(.vertical, 7)
              .glassEffect(
                selected ? .regular.tint(.blue.opacity(0.3)).interactive() : .regular.interactive(),
                in: .rect(cornerRadius: 999)
              )
          }
          .buttonStyle(.plain)
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
      ProgressView("正在加载分数数据")
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
        HStack {
          Text("共 \(groups.count) 所院校")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
          Spacer()
          Text(isAdmission ? "录取分数线" : "投档分数线")
            .font(.caption)
            .foregroundStyle(.secondary)
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
          .foregroundStyle(.primary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
        HStack(spacing: 10) {
          metaChip(icon: "list.bullet", text: isAdmission ? "\(group.itemCount)个专业" : "\(group.itemCount)个专业组")
          if group.totalPeople > 0 {
            metaChip(icon: "person.2", text: "\(group.totalPeople)人")
          }
        }
      }
      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 1) {
        if let min = group.minScore {
          Text("\(min)")
            .font(.title3.weight(.bold).monospacedDigit())
            .foregroundStyle(.blue)
          Text("最低分")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .padding(14)
    .nativeGlassPanel(cornerRadius: 16, tint: .blue.opacity(0.05), interactive: true)
  }

  private func metaChip(icon: String, text: String) -> some View {
    HStack(spacing: 3) {
      Image(systemName: icon).font(.caption2)
      Text(text).font(.caption2)
    }
    .foregroundStyle(.secondary)
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
    .navigationTitle(group.school)
    .navigationBarTitleDisplayMode(.inline)
  }

  private var summaryCard: some View {
    HStack(spacing: 0) {
      summaryStat(value: group.minScore.map(String.init) ?? "—", label: "最低分", accent: .blue)
      divider
      summaryStat(value: group.maxScore.map(String.init) ?? "—", label: "最高分", accent: .indigo)
      divider
      summaryStat(value: "\(group.itemCount)", label: isAdmission ? "专业" : "专业组", accent: .secondary)
      if group.totalPeople > 0 {
        divider
        summaryStat(value: "\(group.totalPeople)", label: "人数", accent: .green)
      }
    }
    .padding(.vertical, 16)
    .frame(maxWidth: .infinity)
    .nativeGlassPanel(cornerRadius: 16, tint: .blue.opacity(0.05))
  }

  private func summaryStat(value: String, label: String, accent: Color) -> some View {
    VStack(spacing: 3) {
      Text(value)
        .font(.title3.weight(.bold).monospacedDigit())
        .foregroundStyle(accent)
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
  }

  private var divider: some View {
    Rectangle()
      .fill(.secondary.opacity(0.2))
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
          .foregroundStyle(.primary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
        if let sub = item.subtitle, !sub.isEmpty {
          Text(sub)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        if !item.subjectScores.isEmpty {
          HStack(spacing: 6) {
            ForEach(item.subjectScores) { s in
              HStack(spacing: 2) {
                Text(s.label).foregroundStyle(.secondary)
                Text(s.value).foregroundStyle(.primary)
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
              .foregroundStyle(.blue)
          }
          if let max = item.maxScore {
            Text("~\(max)")
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          }
        }
        if let count = item.peopleCount {
          Text("\(count)\(isAdmission ? "录取" : "投档")")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
    }
    .padding(14)
    .nativeGlassPanel(cornerRadius: 16, tint: .blue.opacity(0.04))
  }
}
