import SwiftUI

struct StudentServiceNativeView: View {
  let service: StudentHomeService

  @Environment(RouterPath.self) private var router
  @Environment(\.studentClient) private var studentClient
  @Environment(\.keychainStore) private var keychainStore

  @State private var officialServices: [OfficialStudentService] = []
  @State private var statusMessage: String?

  private var token: String? {
    (try? keychainStore.read(account: "official.token")) ?? nil
  }

  private var isLoggedIn: Bool {
    guard let token, !token.isEmpty else { return false }
    return true
  }

  private var resolvedURL: URL {
    OfficialServiceResolver().launchURL(for: service, token: token, officialServices: officialServices)
  }

  private var matchedOfficialName: String? {
    OfficialServiceResolver()
      .matchOfficialService(for: service, in: officialServices)?
      .name
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        headerCard
        statusCard
        actionCard
        tipsCard
      }
      .padding()
    }
    .navigationTitle(service.title)
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await loadOfficialServices()
    }
  }

  private var headerCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 14) {
        Image(systemName: service.systemImage)
          .font(.largeTitle)
          .foregroundStyle(.blue)
          .frame(width: 54, height: 54)
          .nativeGlassPanel(cornerRadius: 16, tint: .blue.opacity(0.12))
        VStack(alignment: .leading, spacing: 6) {
          Text(service.title)
            .font(.title2.weight(.bold))
          Text(service.subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      Text("此页面为原生入口，实际业务仍在官方考生平台完成，App 会自动携带登录态进入对应流程。")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .padding()
    .nativeGlassPanel(cornerRadius: 18, tint: .blue.opacity(0.06))
  }

  private var statusCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("办理状态", systemImage: "checkmark.shield")
        .font(.headline)

      HStack {
        Text(isLoggedIn ? "已绑定官方账号" : "未绑定官方账号")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Image(systemName: isLoggedIn ? "checkmark.circle.fill" : "exclamationmark.circle")
          .foregroundStyle(isLoggedIn ? .green : .orange)
      }

      if let matchedOfficialName {
        Text("官方实时入口：\(matchedOfficialName)")
          .font(.footnote)
          .foregroundStyle(.secondary)
      } else if isLoggedIn {
        Text("官方暂未返回同名服务，将使用内置路由 \(service.routeSource) 打开。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if let statusMessage {
        Text(statusMessage)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .padding()
    .nativeGlassPanel(cornerRadius: 18, tint: .green.opacity(0.05))
  }

  private var actionCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      if isLoggedIn {
        Button {
          router.navigate(to: .web(title: service.title, url: resolvedURL))
        } label: {
          Label("进入官方办理", systemImage: "arrow.up.right.square")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
      } else {
        Button {
          router.navigate(to: .candidateLogin)
        } label: {
          Label("先绑定考生账号", systemImage: "person.badge.key")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
      }

      Button {
        router.navigate(to: .web(title: "考生综合服务平台", url: OfficialServiceCatalog.studentPortal))
      } label: {
        Label("打开官方首页", systemImage: "safari")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.glass)
    }
    .padding()
    .nativeGlassPanel(cornerRadius: 18, tint: .orange.opacity(0.05))
  }

  private var tipsCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("办理提示")
        .font(.headline)
      Text("• 报名、缴费、打印、查询等高风险操作仅在官方页面完成。")
      Text("• 若页面仍显示登录，请返回「我的」确认账号绑定后重试。")
      Text("• 主站证书异常时，资讯页会自动尝试 HTTP/HTTPS 双协议抓取。")
    }
    .font(.footnote)
    .foregroundStyle(.secondary)
    .padding()
    .nativeGlassPanel(cornerRadius: 18)
  }

  private func loadOfficialServices() async {
    guard let token, !token.isEmpty else {
      officialServices = []
      statusMessage = "绑定账号后可读取官方实时服务列表。"
      return
    }

    do {
      let response = try await studentClient.fetchStudentServices(token: token)
      officialServices = response.data ?? []
      statusMessage = officialServices.isEmpty ? "官方暂未返回开放服务。" : nil
    } catch {
      officialServices = []
      statusMessage = "读取官方服务失败：\(error.localizedDescription)"
    }
  }
}
