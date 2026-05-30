import SwiftUI

// MARK: - Main View

struct SafeGaokaoView: View {
  @Environment(RouterPath.self) private var router
  @Environment(\.contentClient) private var contentClient

  @State private var gksContent: GksPageContent? = nil
  @State private var sectionData: [String: [CachedArticle]] = [:]
  @State private var isLoading = false

  private static let mainSections: [OfficialCategory] = [
    OfficialCategory(id: "pagkpt-zcgd", title: "政策规定", kind: .policy, examType: nil,
                     url: URL(string: "https://www.nm.zsks.cn/ztzl/pagkpt/zcgd/")!),
    OfficialCategory(id: "pagkpt-tzgg", title: "通知公告", kind: .notice, examType: nil,
                     url: URL(string: "https://www.nm.zsks.cn/ztzl/pagkpt/tzgg/")!),
    OfficialCategory(id: "pagkpt-gspt", title: "公示平台", kind: .topic, examType: nil,
                     url: URL(string: "https://www.nm.zsks.cn/ztzl/pagkpt/gspt/")!),
    OfficialCategory(id: "pagkpt-xxcx", title: "信息查询", kind: .service, examType: nil,
                     url: URL(string: "https://www.nm.zsks.cn/ztzl/pagkpt/xxcx/")!),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        heroBanner
        gaokaoShengSection
        ForEach(Self.mainSections) { section in
          sectionCard(section)
        }
        volunteerCard
      }
      .padding()
    }
    .background(ClaudeTheme.surface.ignoresSafeArea())
    .navigationTitle("平安高考")
    .navigationBarTitleDisplayMode(.large)
    .refreshable { await loadAll() }
    .task {
      guard gksContent == nil, sectionData.isEmpty else { return }
      await loadAll()
    }
  }

  // MARK: Hero banner

  private var heroBanner: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 12) {
        Image(systemName: "shield.checkered")
          .font(.title2.weight(.semibold))
          .foregroundStyle(ClaudeTheme.primary)
        VStack(alignment: .leading, spacing: 2) {
          Text("平安高考")
            .font(.title2.weight(.bold))
            .foregroundStyle(ClaudeTheme.textPrimary)
          Text("政策 · 公示 · 查询 · 志愿填报 · 录取查询")
            .font(.caption)
            .foregroundStyle(ClaudeTheme.textSecondary)
        }
      }

      HStack(spacing: 10) {
        heroButton(title: "填报志愿", subtitle: "官方入口",
                   icon: "pencil.and.list.clipboard",
                   url: URL(string: "https://www1.nm.zsks.cn/xgknm/")!)
        heroButton(title: "志愿专栏", subtitle: "计划·章程",
                   icon: "doc.text.magnifyingglass",
                   url: URL(string: "https://www.nm.zsks.cn/25gkwb/")!)

        Button {
          router.navigate(to: .admissionQuery)
        } label: {
          VStack(spacing: 5) {
            Image(systemName: "checkmark.seal")
              .font(.title3)
              .foregroundStyle(ClaudeTheme.primary)
            Text("录取查询")
              .font(.caption.weight(.semibold))
              .foregroundStyle(ClaudeTheme.textPrimary)
            Text("实时结果")
              .font(.caption2)
              .foregroundStyle(ClaudeTheme.textSecondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
          .background(ClaudeTheme.primarySoft)
          .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .stroke(ClaudeTheme.primary.opacity(0.25), lineWidth: 0.75)
          )
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
    .claudeCard(padding: 18)
  }

  private func heroButton(title: String, subtitle: String, icon: String, url: URL) -> some View {
    Button {
      router.navigate(to: .web(title: title, url: url))
    } label: {
      VStack(spacing: 5) {
        Image(systemName: icon)
          .font(.title3)
          .foregroundStyle(ClaudeTheme.textSecondary)
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(ClaudeTheme.textPrimary)
        Text(subtitle)
          .font(.caption2)
          .foregroundStyle(ClaudeTheme.textSecondary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .background(ClaudeTheme.surfaceCard)
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(ClaudeTheme.border, lineWidth: 0.75)
      )
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  // MARK: @高考生 专刊

  private var gaokaoShengSection: some View {
    let gksCategory = OfficialCategory(
      id: "pagkpt-gks", title: "@高考生", kind: .notice, examType: nil,
      url: URL(string: "https://www.nm.zsks.cn/ztzl/pagkpt/gks/")!
    )
    return VStack(alignment: .leading, spacing: 14) {
      sectionHeader(title: "@高考生", icon: "person.crop.circle.badge.checkmark") {
        router.navigate(to: .sectionList(gksCategory))
      }

      resourceGrid

      if let content = gksContent {
        if content.articles.isEmpty {
          emptyLabel
        } else {
          articleList(content.articles.prefix(8).map { $0 }, category: gksCategory)
        }
      } else {
        loadingRow
      }
    }
    .claudeCard()
  }

  private var resourceGrid: some View {
    let resources = gksContent?.resources ?? []
    let displayed = resources.isEmpty ? Self.fallbackResources : resources

    return LazyVGrid(
      columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
      spacing: 8
    ) {
      ForEach(displayed) { res in
        Button {
          router.navigate(to: .web(title: res.title, url: res.url))
        } label: {
          let meta = Self.resourceMeta(for: res.url, title: res.title)
          VStack(alignment: .leading, spacing: 6) {
            Image(systemName: meta.icon)
              .font(.subheadline)
              .foregroundStyle(meta.tint)
            Text(meta.displayTitle)
              .font(.caption.weight(.semibold))
              .foregroundStyle(ClaudeTheme.textPrimary)
              .lineLimit(1)
            Text(res.title)
              .font(.caption2)
              .foregroundStyle(ClaudeTheme.textTertiary)
              .lineLimit(2)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
          .background(ClaudeTheme.surface)
          .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .stroke(ClaudeTheme.border, lineWidth: 0.75)
          )
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
  }

  // MARK: 四栏原生卡

  private func sectionCard(_ section: OfficialCategory) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader(title: section.title, icon: sectionIcon(section)) {
        router.navigate(to: .sectionList(section))
      }

      if let articles = sectionData[section.id] {
        if articles.isEmpty {
          emptyLabel
        } else {
          articleList(articles.prefix(7).map { $0 }, category: section)
        }
      } else {
        loadingRow
      }
    }
    .claudeCard()
  }

  // MARK: 志愿填报专栏

  private var volunteerCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader(title: "志愿填报专栏", icon: "doc.badge.gearshape") { }

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
        volunteerButton("招生计划变更", "arrow.triangle.2.circlepath.doc.on.clipboard",
                        url: URL(string: "https://www.nm.zsks.cn/25gkwb/25zsjhbg/")!)
        volunteerButton("政策实施办法", "doc.text",
                        url: URL(string: "https://www.nm.zsks.cn/ztzl/pagkpt/zcgd/")!)
        volunteerButton("招生章程", "books.vertical",
                        url: URL(string: "https://www.nm.zsks.cn/25gkwb/25zszc/")!)
        volunteerButton("填报志愿专栏", "pencil.and.list.clipboard",
                        url: URL(string: "https://www.nm.zsks.cn/25gkwb/")!)
      }
    }
    .claudeCard()
  }

  private func volunteerButton(_ title: String, _ icon: String, url: URL) -> some View {
    Button {
      router.navigate(to: .web(title: title, url: url))
    } label: {
      HStack(spacing: 8) {
        Image(systemName: icon)
          .font(.caption)
          .foregroundStyle(ClaudeTheme.primary)
          .frame(width: 18)
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(ClaudeTheme.textPrimary)
          .lineLimit(2)
          .minimumScaleFactor(0.85)
        Spacer()
        Image(systemName: "chevron.right")
          .font(.caption2)
          .foregroundStyle(ClaudeTheme.textTertiary)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 10)
      .background(ClaudeTheme.surface)
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(ClaudeTheme.border, lineWidth: 0.75)
      )
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  // MARK: Shared subviews

  private func sectionHeader(title: String, icon: String, moreAction: @escaping () -> Void) -> some View {
    HStack {
      Label(title, systemImage: icon)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(ClaudeTheme.textPrimary)
      Spacer()
      Button("更多", action: moreAction)
        .buttonStyle(.claudeGhost)
        .font(.caption)
    }
  }

  private func articleList(_ articles: [CachedArticle], category: OfficialCategory) -> some View {
    VStack(spacing: 0) {
      ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
        Button {
          ArticleSessionCache.store(article)
          router.navigate(to: .smart(for: article))
        } label: {
          HStack(alignment: .top, spacing: 0) {
            Rectangle()
              .fill(ClaudeTheme.primary.opacity(0.3))
              .frame(width: 2)
              .padding(.trailing, 10)
            Text(article.title)
              .font(.subheadline)
              .foregroundStyle(ClaudeTheme.textPrimary)
              .lineLimit(2)
              .frame(maxWidth: .infinity, alignment: .leading)
            if let date = article.publishedAt {
              Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                .font(.caption.monospacedDigit())
                .foregroundStyle(ClaudeTheme.textTertiary)
                .padding(.leading, 8)
            }
          }
          .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        if index < articles.count - 1 {
          Divider()
        }
      }
    }
  }

  private var loadingRow: some View {
    HStack(spacing: 10) {
      ProgressView().tint(ClaudeTheme.primary).controlSize(.small)
      Text("加载中…")
        .font(.caption)
        .foregroundStyle(ClaudeTheme.textTertiary)
    }
    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
  }

  private var emptyLabel: some View {
    Text("暂无内容")
      .font(.caption)
      .foregroundStyle(ClaudeTheme.textTertiary)
      .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
  }

  // MARK: Data loading

  private enum LoadEvent {
    case section(String, [CachedArticle])
    case gks(GksPageContent)
  }

  private func loadAll() async {
    isLoading = true
    defer { isLoading = false }
    await withTaskGroup(of: LoadEvent?.self) { group in
      group.addTask {
        guard let content = try? await contentClient.fetchGksContent() else { return nil }
        return .gks(content)
      }
      for section in Self.mainSections {
        group.addTask {
          let articles = (try? await contentClient.fetchFeed(category: section, limit: 10)) ?? []
          return .section(section.id, articles)
        }
      }
      for await event in group {
        switch event {
        case .section(let id, let articles): sectionData[id] = articles
        case .gks(let content): gksContent = content
        case nil: break
        }
      }
    }
  }

  // MARK: Resource metadata

  private struct ResourceMeta {
    let displayTitle: String
    let icon: String
    let tint: Color
  }

  private static func resourceMeta(for url: URL, title: String = "") -> ResourceMeta {
    let host = url.host?.lowercased() ?? ""
    let path = url.path.lowercased()
    if host.contains("chsi.com.cn")   { return ResourceMeta(displayTitle: "阳光高考", icon: "sun.max.fill", tint: ClaudeTheme.primary) }
    if host.contains("yigaozhao.com") { return ResourceMeta(displayTitle: "招生咨询", icon: "bubble.left.and.bubble.right.fill", tint: ClaudeTheme.info) }
    if host.contains("smartedu.cn")   { return ResourceMeta(displayTitle: "志愿指导", icon: "graduationcap.fill", tint: ClaudeTheme.textSecondary) }
    if path.contains("zsjh") || title.contains("招生计划") {
      return ResourceMeta(displayTitle: "招生计划", icon: "list.bullet.rectangle.fill", tint: ClaudeTheme.success)
    }
    let short = String(title.prefix(5))
    return ResourceMeta(displayTitle: short.isEmpty ? "资源" : short, icon: "link.circle.fill", tint: ClaudeTheme.textTertiary)
  }

  private static let fallbackResources: [GksResource] = [
    GksResource(id: "chsi",    title: "教育部高校招生阳光工程指定平台",
                url: URL(string: "https://gaokao.chsi.com.cn/")!),
    GksResource(id: "yigao",   title: "全国普通高校招生咨询指导平台",
                url: URL(string: "https://www.yigaozhao.com/")!),
    GksResource(id: "zsjh",    title: "2025年高考招生计划",
                url: URL(string: "https://www.nm.zsks.cn/25gkwb/25zsjh/")!),
    GksResource(id: "smartedu",title: "普通高校招生志愿填报指导",
                url: URL(string: "https://basic.nmg.smartedu.cn/res//goResDetailInfo.html?productCode=PD1655353890806956032")!),
  ]

  private func sectionIcon(_ section: OfficialCategory) -> String {
    switch section.id {
    case "pagkpt-zcgd": "doc.text"
    case "pagkpt-tzgg": "bell"
    case "pagkpt-gspt": "list.bullet.clipboard"
    case "pagkpt-xxcx": "magnifyingglass.circle"
    default: "folder"
    }
  }
}
