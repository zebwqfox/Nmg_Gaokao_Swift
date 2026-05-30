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
      VStack(alignment: .leading, spacing: 18) {
        heroBanner
        gaokaoShengSection
        ForEach(Self.mainSections) { section in
          sectionCard(section)
        }
        volunteerCard
      }
      .padding()
    }
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
          .font(.largeTitle.bold())
          .foregroundStyle(.blue)
        VStack(alignment: .leading, spacing: 2) {
          Text("平安高考")
            .font(.largeTitle.bold())
          Text("政策 · 公示 · 查询 · 志愿填报 · 录取查询")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      HStack(spacing: 10) {
        heroButton(title: "填报志愿", subtitle: "官方入口",
                   icon: "pencil.and.list.clipboard", tint: .blue,
                   url: URL(string: "https://www1.nm.zsks.cn/xgknm/")!)
        heroButton(title: "志愿专栏", subtitle: "计划·章程",
                   icon: "doc.text.magnifyingglass", tint: .orange,
                   url: URL(string: "https://www.nm.zsks.cn/25gkwb/")!)

        Button {
          router.navigate(to: .admissionQuery)
        } label: {
          VStack(spacing: 4) {
            Image(systemName: "checkmark.seal")
              .font(.title2)
              .foregroundStyle(.green)
            Text("录取查询")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
            Text("实时结果")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
          .nativeGlassPanel(cornerRadius: 14, tint: .green.opacity(0.1), interactive: true)
        }
        .buttonStyle(.plain)
      }
    }
    .padding()
    .nativeGlassPanel(cornerRadius: 20, tint: .blue.opacity(0.07))
  }

  private func heroButton(title: String, subtitle: String, icon: String, tint: Color, url: URL) -> some View {
    Button {
      router.navigate(to: .web(title: title, url: url))
    } label: {
      VStack(spacing: 4) {
        Image(systemName: icon)
          .font(.title2)
          .foregroundStyle(tint)
        Text(title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
        Text(subtitle)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .nativeGlassPanel(cornerRadius: 14, tint: tint.opacity(0.1), interactive: true)
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
      sectionHeader(title: "@高考生", icon: "person.crop.circle.badge.checkmark", tint: .blue) {
        router.navigate(to: .sectionList(gksCategory))
      }

      resourceGrid

      Divider()

      if let content = gksContent {
        if content.articles.isEmpty {
          emptyLabel
        } else {
          articleList(content.articles.prefix(8).map { $0 })
        }
      } else {
        loadingRow
      }
    }
    .padding()
    .nativeGlassPanel(cornerRadius: 18, tint: .blue.opacity(0.06))
  }

  private var resourceGrid: some View {
    let resources = gksContent?.resources ?? []
    let displayed = resources.isEmpty ? Self.fallbackResources : resources

    return LazyVGrid(
      columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
      spacing: 10
    ) {
      ForEach(displayed) { res in
        Button {
          router.navigate(to: .web(title: res.title, url: res.url))
        } label: {
          let meta = Self.resourceMeta(for: res.url, title: res.title)
          VStack(alignment: .leading, spacing: 6) {
            Image(systemName: meta.icon)
              .font(.title3)
              .foregroundStyle(meta.tint)
            Text(meta.displayTitle)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
              .lineLimit(1)
            Text(res.title)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
          .nativeGlassPanel(cornerRadius: 12, tint: meta.tint.opacity(0.08), interactive: true)
        }
        .buttonStyle(.plain)
      }
    }
  }

  // MARK: 四栏原生卡

  private func sectionCard(_ section: OfficialCategory) -> some View {
    let tint = sectionTint(section)
    return VStack(alignment: .leading, spacing: 12) {
      sectionHeader(title: section.title, icon: sectionIcon(section), tint: tint) {
        router.navigate(to: .sectionList(section))
      }

      Divider()

      if let articles = sectionData[section.id] {
        if articles.isEmpty {
          emptyLabel
        } else {
          articleList(articles.prefix(7).map { $0 })
        }
      } else {
        loadingRow
      }
    }
    .padding()
    .nativeGlassPanel(cornerRadius: 18, tint: tint.opacity(0.05))
  }

  // MARK: 志愿填报专栏

  private var volunteerCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("志愿填报专栏", systemImage: "doc.badge.gearshape")
        .font(.headline)
        .foregroundStyle(.purple)

      Divider()

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
        volunteerButton("招生计划变更", "arrow.triangle.2.circlepath.doc.on.clipboard", tint: .blue,
                        url: URL(string: "https://www.nm.zsks.cn/25gkwb/25zsjhbg/")!)
        volunteerButton("政策实施办法", "doc.text", tint: .orange,
                        url: URL(string: "https://www.nm.zsks.cn/ztzl/pagkpt/zcgd/")!)
        volunteerButton("招生章程", "books.vertical", tint: .green,
                        url: URL(string: "https://www.nm.zsks.cn/25gkwb/25zszc/")!)
        volunteerButton("填报志愿专栏", "pencil.and.list.clipboard", tint: .purple,
                        url: URL(string: "https://www.nm.zsks.cn/25gkwb/")!)
      }
    }
    .padding()
    .nativeGlassPanel(cornerRadius: 18, tint: .purple.opacity(0.06))
  }

  private func volunteerButton(_ title: String, _ icon: String, tint: Color, url: URL) -> some View {
    Button {
      router.navigate(to: .web(title: title, url: url))
    } label: {
      HStack(spacing: 10) {
        Image(systemName: icon)
          .font(.body)
          .foregroundStyle(tint)
          .frame(width: 24)
        Text(title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(2)
          .minimumScaleFactor(0.85)
        Spacer()
        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      .padding(12)
      .nativeGlassPanel(cornerRadius: 12, tint: tint.opacity(0.07), interactive: true)
    }
    .buttonStyle(.plain)
  }

  // MARK: Shared subviews

  private func sectionHeader(title: String, icon: String, tint: Color, moreAction: @escaping () -> Void) -> some View {
    HStack {
      Label(title, systemImage: icon)
        .font(.headline)
        .foregroundStyle(tint)
      Spacer()
      Button("更多", action: moreAction)
        .font(.caption.weight(.semibold))
        .buttonStyle(.glass)
    }
  }

  private func articleList(_ articles: [CachedArticle]) -> some View {
    VStack(spacing: 0) {
      ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
        Button {
          ArticleSessionCache.store(article)
          router.navigate(to: .smart(for: article))
        } label: {
          HStack(alignment: .top, spacing: 8) {
            Text(article.title)
              .font(.subheadline)
              .foregroundStyle(.primary)
              .lineLimit(2)
              .frame(maxWidth: .infinity, alignment: .leading)
            if let date = article.publishedAt {
              Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
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
    ProgressView()
      .frame(maxWidth: .infinity, minHeight: 50)
  }

  private var emptyLabel: some View {
    Text("暂无内容")
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
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
    if host.contains("chsi.com.cn")   { return ResourceMeta(displayTitle: "阳光高考", icon: "sun.max.fill", tint: .yellow) }
    if host.contains("yigaozhao.com") { return ResourceMeta(displayTitle: "招生咨询", icon: "bubble.left.and.bubble.right.fill", tint: .blue) }
    if host.contains("smartedu.cn")   { return ResourceMeta(displayTitle: "志愿指导", icon: "graduationcap.fill", tint: .purple) }
    if path.contains("zsjh") || title.contains("招生计划") {
      return ResourceMeta(displayTitle: "招生计划", icon: "list.bullet.rectangle.fill", tint: .green)
    }
    let short = String(title.prefix(5))
    return ResourceMeta(displayTitle: short.isEmpty ? "资源" : short, icon: "link.circle.fill", tint: .secondary)
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

  private func sectionTint(_ section: OfficialCategory) -> Color {
    switch section.id {
    case "pagkpt-zcgd": .blue
    case "pagkpt-tzgg": .orange
    case "pagkpt-gspt": .green
    case "pagkpt-xxcx": .purple
    default: .primary
    }
  }
}
