import SwiftData
import SwiftUI

struct DashboardView: View {
  @Environment(RouterPath.self) private var router
  @Environment(\.contentClient) private var contentClient
  @Environment(\.studentClient) private var studentClient
  @Environment(\.keychainStore) private var keychainStore
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \CandidateProfile.createdAt, order: .reverse) private var candidates: [CandidateProfile]
  @Query(sort: \CachedArticle.cachedAt, order: .reverse) private var articles: [CachedArticle]

  @State private var isRefreshing = false
  @State private var examTypes: [OfficialExamType] = []
  @State private var officialCalendar: [OfficialCalendarItem] = []
  @State private var officialServiceCount = 0

  private var policyArticles: [CachedArticle] {
    articles.filter { $0.kind == .policy || $0.categoryID.contains("gaokao") }.prefix(5).map { $0 }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        candidateCard
        officialStatusSection
        quickServices
        latestPolicySection
      }
      .padding()
    }
    .navigationTitle("工作台")
    .refreshable {
      await refreshPolicies()
      await refreshOfficialDashboard()
    }
    .task {
      if policyArticles.isEmpty {
        await refreshPolicies()
      }
      await refreshOfficialDashboard()
    }
  }

  private var candidateCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("考生档案", systemImage: "person.text.rectangle")
          .font(.headline)
        Spacer()
        Button(candidates.isEmpty ? "绑定" : "管理") {
          router.navigate(to: .candidateLogin)
        }
        .buttonStyle(.glassProminent)
      }

      if let candidate = candidates.first {
        VStack(alignment: .leading, spacing: 6) {
          Text(candidate.displayName)
            .font(.title3.weight(.semibold))
          Text("\(candidate.examType) · 证件尾号 \(candidate.idNumberLast4)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      } else {
        Text("绑定官方考生账号后，可从这里快速进入报名、准考证、成绩、录取等流程。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding()
    .nativeGlassPanel(cornerRadius: 18, tint: .blue.opacity(0.08), interactive: true)
  }

  private var officialStatusSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("官方状态")
          .font(.headline)
        Spacer()
        Button {
          Task { await refreshOfficialDashboard() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.glass)
      }

      if examTypes.isEmpty && officialCalendar.isEmpty && officialServiceCount == 0 {
        Text("登录绑定后，这里会直接读取官方考试类型、服务入口和近期日程。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        HStack(spacing: 10) {
          OfficialMetric(title: "考试类型", value: "\(examTypes.count)", tint: .blue)
          OfficialMetric(title: "官方服务", value: "\(officialServiceCount)", tint: .green)
          OfficialMetric(title: "日程", value: "\(officialCalendar.count)", tint: .orange)
        }

        ForEach(examTypes.prefix(3)) { exam in
          HStack {
            Text(exam.kslxmc)
              .font(.subheadline.weight(.semibold))
            Spacer()
            Text(exam.syzt ?? "可用")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .padding()
    .nativeGlassPanel(cornerRadius: 18, tint: .orange.opacity(0.05))
  }

  private var quickServices: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("常用服务")
        .font(.headline)
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
        ForEach(StudentHomeService.allCases) { service in
          Button {
            router.navigate(to: .studentService(service))
          } label: {
            VStack(alignment: .leading, spacing: 10) {
              Image(systemName: service.systemImage)
                .font(.title2)
                .foregroundStyle(.blue)
              Text(service.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .nativeGlassPanel(cornerRadius: 16, tint: .blue.opacity(0.06), interactive: true)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var latestPolicySection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("今日政策")
          .font(.headline)
        Spacer()
        Button {
          Task { await refreshPolicies() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .disabled(isRefreshing)
      }

      if isRefreshing && policyArticles.isEmpty {
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 80)
      } else if policyArticles.isEmpty {
        ContentUnavailableView("暂无缓存", systemImage: "newspaper", description: Text("下拉刷新即可从官网获取最新高考政策。"))
      } else {
        VStack(spacing: 0) {
          ForEach(policyArticles) { article in
            Button {
              router.navigate(to: .article(id: article.id))
            } label: {
              ArticleCompactRow(article: article)
            }
            .buttonStyle(.plain)
            if article.id != policyArticles.last?.id {
              Divider()
            }
          }
        }
        .nativeGlassPanel(cornerRadius: 18, tint: .green.opacity(0.05))
      }
    }
  }

  private func refreshPolicies() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }

    let categories = contentClient.categories.filter { ["gaokao-policy", "gaokao-notice", "policies"].contains($0.id) }
    for category in categories {
      guard let fetched = try? await contentClient.fetchFeed(category: category, limit: 10) else { continue }
      for article in fetched {
        upsert(article)
      }
    }
    try? modelContext.save()
  }

  private func refreshOfficialDashboard() async {
    let storedToken = (try? keychainStore.read(account: "official.token")) ?? nil
    guard let token = storedToken, !token.isEmpty else {
      return
    }

    async let types = try? studentClient.fetchExamTypes(token: token)
    async let calendar = try? studentClient.fetchExamCalendar(token: token)
    async let services = try? studentClient.fetchStudentServices(token: token)

    let loadedTypes = await types
    let loadedCalendar = await calendar
    let loadedServices = await services

    if let loadedTypes = loadedTypes, let data = loadedTypes.data {
      examTypes = data
    } else {
      examTypes = []
    }

    if let loadedCalendar = loadedCalendar, let data = loadedCalendar.data {
      officialCalendar = data
    } else {
      officialCalendar = []
    }

    if let loadedServices = loadedServices, let data = loadedServices.data {
      officialServiceCount = data.count
    } else {
      officialServiceCount = 0
    }
  }

  private func upsert(_ article: CachedArticle) {
    if let existing = articles.first(where: { $0.id == article.id }) {
      existing.update(from: article)
    } else {
      modelContext.insert(article)
    }
  }
}

private struct OfficialMetric: View {
  let title: String
  let value: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(value)
        .font(.title3.weight(.bold))
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .nativeGlassPanel(cornerRadius: 14, tint: tint.opacity(0.08))
  }
}

struct ArticleCompactRow: View {
  let article: CachedArticle

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(article.title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(2)
      HStack(spacing: 8) {
        Text(article.categoryTitle)
        if let publishedAt = article.publishedAt {
          Text(DateFormatters.displayDate.string(from: publishedAt))
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
  }
}
