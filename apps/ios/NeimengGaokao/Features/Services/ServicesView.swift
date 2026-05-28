import SwiftUI

struct ServicesView: View {
  @Environment(RouterPath.self) private var router
  @Environment(\.studentClient) private var studentClient
  @Environment(\.keychainStore) private var keychainStore

  @State private var officialServices: [OfficialStudentService] = []
  @State private var loadMessage: String?

  private var groupedServices: [(String, [OfficialService])] {
    Dictionary(grouping: OfficialServiceCatalog.services, by: \.group)
      .sorted { lhs, rhs in lhs.key < rhs.key }
  }

  var body: some View {
    List {
      if !officialServices.isEmpty {
        Section("当前官方开放") {
          ForEach(officialServices) { service in
            Button {
              let token = (try? keychainStore.read(account: "official.token")) ?? nil
              router.navigate(
                to: .web(
                  title: service.name ?? "官方服务",
                  url: service.launchURL(token: token)
                )
              )
            } label: {
              OfficialStudentServiceRow(service: service)
            }
            .buttonStyle(.plain)
          }
        }
      } else if let loadMessage {
        Section("当前官方开放") {
          Text(loadMessage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }

      ForEach(groupedServices, id: \.0) { group, services in
        Section(group) {
          ForEach(services) { service in
            Button {
              if let homeService = StudentHomeService.allCases.first(where: { $0.title == service.title }) {
                router.navigate(to: .studentService(homeService))
              } else {
                let token = (try? keychainStore.read(account: "official.token")) ?? nil
                let url = OfficialServiceResolver().launchURL(
                  for: service,
                  token: token,
                  officialServices: officialServices
                )
                router.navigate(to: .web(title: service.title, url: url))
              }
            } label: {
              ServiceRow(service: service)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .navigationTitle("服务")
    .task {
      await loadOfficialServices()
    }
    .refreshable {
      await loadOfficialServices()
    }
    .toolbar {
      Button {
        router.navigate(to: .candidateLogin)
      } label: {
        Label("登录", systemImage: "person.badge.key")
      }
    }
  }

  private func loadOfficialServices() async {
    guard let token = (try? keychainStore.read(account: "official.token")) ?? nil, !token.isEmpty else {
      officialServices = []
      loadMessage = "绑定考生账号后，会显示官方接口返回的实时服务入口。"
      return
    }

    do {
      let response = try await studentClient.fetchStudentServices(token: token)
      officialServices = response.data ?? []
      loadMessage = officialServices.isEmpty ? "官方暂未返回开放服务。" : nil
    } catch {
      officialServices = []
      loadMessage = "读取官方服务失败：\(error.localizedDescription)"
    }
  }
}

private struct OfficialStudentServiceRow: View {
  let service: OfficialStudentService

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: serviceIcon)
        .font(.title3)
        .foregroundStyle(.blue)
        .frame(width: 38, height: 38)
        .nativeGlassPanel(cornerRadius: 12, tint: .blue.opacity(0.12))
      VStack(alignment: .leading, spacing: 4) {
        Text(service.name ?? "官方服务")
          .font(.headline)
        HStack(spacing: 8) {
          if let type = service.type, !type.isEmpty {
            Text(type)
          }
          if let planCode = service.planCode, !planCode.isEmpty {
            Text(planCode)
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Spacer()
      Image(systemName: "chevron.right")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 4)
  }

  private var serviceIcon: String {
    let name = service.name ?? ""
    if name.contains("准考证") { return "printer" }
    if name.contains("成绩") { return "chart.bar.doc.horizontal" }
    if name.contains("志愿") { return "list.bullet.clipboard" }
    if name.contains("录取") { return "checkmark.seal" }
    if name.contains("缴费") { return "creditcard" }
    if name.contains("照片") { return "camera" }
    return "square.grid.2x2"
  }
}

private struct ServiceRow: View {
  let service: OfficialService

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: service.systemImage)
        .font(.title3)
        .foregroundStyle(.white)
        .frame(width: 38, height: 38)
        .nativeGlassPanel(cornerRadius: 12, tint: service.requiresLogin ? .blue.opacity(0.25) : .green.opacity(0.25))
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(service.title)
            .font(.headline)
          if service.requiresLogin {
            Text("需登录")
              .font(.caption2)
              .foregroundStyle(.secondary)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .glassEffect(.regular, in: .rect(cornerRadius: 999))
          }
        }
        Text(service.subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer()
      Image(systemName: "chevron.right")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 4)
  }
}
