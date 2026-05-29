import SwiftUI

struct SafeGaokaoView: View {
  @Environment(RouterPath.self) private var router
  @Environment(\.contentClient) private var contentClient

  @State private var sectionData: [String: [CachedArticle]] = [:]
  @State private var isLoading = false

  private static let sections: [OfficialCategory] = [
    OfficialCategory(
      id: "pagkpt-zcgd", title: "政策规定", kind: .policy, examType: nil,
      url: URL(string: "https://www.nm.zsks.cn/ztzl/pagkpt/zcgd/")!
    ),
    OfficialCategory(
      id: "pagkpt-tzgg", title: "通知公告", kind: .notice, examType: nil,
      url: URL(string: "https://www.nm.zsks.cn/ztzl/pagkpt/tzgg/")!
    ),
    OfficialCategory(
      id: "pagkpt-gspt", title: "公示平台", kind: .topic, examType: nil,
      url: URL(string: "https://www.nm.zsks.cn/ztzl/pagkpt/gspt/")!
    ),
    OfficialCategory(
      id: "pagkpt-xxcx", title: "信息查询", kind: .service, examType: nil,
      url: URL(string: "https://www.nm.zsks.cn/ztzl/pagkpt/xxcx/")!
    ),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        heroBanner
        ForEach(Self.sections) { section in
          sectionCard(section)
        }
        volunteerCard
      }
      .padding()
    }
    .navigationTitle("平安高考")
    .refreshable {
      await loadAll()
    }
    .task {
      guard sectionData.isEmpty else { return }
      await loadAll()
    }
  }

  // MARK: Hero

  private var heroBanner: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Image(systemName: "shield.checkered")
            .font(.largeTitle.bold())
            .foregroundStyle(.blue)
          Text("平安高考")
            .font(.largeTitle.bold())
        }
        Text("政策、公示、信息查询、志愿填报、录取查询一站式平台")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 10) {
        quickButton(
          title: "填报志愿",
          icon: "pencil.and.list.clipboard",
          tint: .blue,
          url: URL(string: "https://www1.nm.zsks.cn/xgknm/")!
        )
        quickButton(
          title: "志愿专栏",
          icon: "doc.text.magnifyingglass",
          tint: .orange,
          url: URL(string: "https://www.nm.zsks.cn/25gkwb/")!
        )
        quickButton(
          title: "录取查询",
          icon: "checkmark.seal",
          tint: .green,
          url: URL(string: "https://www1.nm.zsks.cn/Gkcjcx/kslqjgcx25_qcsj.jsp")!
        )
      }
    }
    .padding()
    .nativeGlassPanel(cornerRadius: 20, tint: .blue.opacity(0.07))
  }

  private func quickButton(title: String, icon: String, tint: Color, url: URL) -> some View {
    Button {
      router.navigate(to: .web(title: title, url: url))
    } label: {
      VStack(spacing: 6) {
        Image(systemName: icon)
          .font(.title3)
          .foregroundStyle(tint)
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.primary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .nativeGlassPanel(cornerRadius: 14, tint: tint.opacity(0.1), interactive: true)
    }
    .buttonStyle(.plain)
  }

  // MARK: Section cards

  private func sectionCard(_ section: OfficialCategory) -> some View {
    let tint = sectionTint(section)
    return VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label(section.title, systemImage: sectionIcon(section))
          .font(.headline)
          .foregroundStyle(tint)
        Spacer()
        Button {
          router.navigate(to: .web(title: section.title, url: section.url))
        } label: {
          Text("更多")
            .font(.caption.weight(.semibold))
        }
        .buttonStyle(.glass)
      }

      Divider()

      let articles = sectionData[section.id]
      if let articles {
        if articles.isEmpty {
          Text("暂无内容")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 48)
        } else {
          articleList(articles, section: section)
        }
      } else {
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 60)
      }
    }
    .padding()
    .nativeGlassPanel(cornerRadius: 18, tint: tint.opacity(0.05))
  }

  private func articleList(_ articles: [CachedArticle], section: OfficialCategory) -> some View {
    let displayed = Array(articles.prefix(6))
    return VStack(spacing: 0) {
      ForEach(Array(displayed.enumerated()), id: \.element.id) { index, article in
        Button {
          ArticleSessionCache.store(article)
          router.navigate(to: .article(id: article.id))
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
          .padding(.vertical, 8)
        }
        .buttonStyle(.plain)

        if index < displayed.count - 1 {
          Divider()
        }
      }
    }
  }

  // MARK: 志愿填报专栏

  private var volunteerCard: some View {
    Button {
      router.navigate(to: .web(
        title: "志愿填报专栏",
        url: URL(string: "https://www.nm.zsks.cn/25gkwb/")!
      ))
    } label: {
      HStack(spacing: 14) {
        Image(systemName: "doc.badge.gearshape")
          .font(.largeTitle)
          .foregroundStyle(.purple)
          .frame(width: 44)

        VStack(alignment: .leading, spacing: 4) {
          Text("志愿填报专栏")
            .font(.headline)
          Text("招生计划变更 · 政策实施办法 · 招生章程")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .foregroundStyle(.tertiary)
      }
      .padding()
      .nativeGlassPanel(cornerRadius: 18, tint: .purple.opacity(0.07), interactive: true)
    }
    .buttonStyle(.plain)
  }

  // MARK: Helpers

  private func loadAll() async {
    isLoading = true
    defer { isLoading = false }
    await withTaskGroup(of: (String, [CachedArticle]).self) { group in
      for section in Self.sections {
        group.addTask {
          let articles = (try? await contentClient.fetchFeed(category: section, limit: 7)) ?? []
          return (section.id, articles)
        }
      }
      for await (id, articles) in group {
        sectionData[id] = articles
      }
    }
  }

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
