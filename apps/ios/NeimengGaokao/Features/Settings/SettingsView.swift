import SwiftData
import SwiftUI

struct SettingsView: View {
  @Environment(RouterPath.self) private var router
  @Environment(\.keychainStore) private var keychainStore
  @Environment(\.openURL) private var openURL
  @Environment(\.modelContext) private var modelContext

  @Query private var candidates: [CandidateProfile]

  @State private var credentialStatus = "未检查"

  var body: some View {
    List {
      Section("账号") {
        Button {
          router.navigate(to: .candidateLogin)
        } label: {
          Label(candidates.isEmpty ? "绑定官方考生账号" : "重新登录官方账号", systemImage: "person.badge.key")
        }

        HStack {
          Label("凭据状态", systemImage: "key")
          Spacer()
          Text(credentialStatus)
            .foregroundStyle(.secondary)
        }

        Button(role: .destructive) {
          clearCredentials()
        } label: {
          Label("清除 Keychain 凭据", systemImage: "trash")
        }
      }

      Section("官方来源") {
        Button {
          openURL(OfficialServiceCatalog.mainSite)
        } label: {
          Label("内蒙古招生考试信息网", systemImage: "safari")
        }
        Button {
          router.navigate(to: .web(title: "考生办事平台", url: OfficialServiceCatalog.studentPortal))
        } label: {
          Label("打开考生办事平台", systemImage: "person.text.rectangle")
        }
      }

      Section("本地数据") {
        HStack {
          Label("收藏资讯", systemImage: "star")
          Spacer()
          Text("\(FavoriteArticles.count)")
            .foregroundStyle(.secondary)
        }
        Button(role: .destructive) {
          FavoriteArticles.clearAll()
        } label: {
          Label("清除收藏", systemImage: "trash")
        }
      }
    }
    .navigationTitle("我的")
    .onAppear(perform: refreshCredentialStatus)
  }

  private func refreshCredentialStatus() {
    do {
      let hasID = try keychainStore.read(account: "official.idNumber")?.isEmpty == false
      let hasToken = try keychainStore.read(account: "official.token")?.isEmpty == false
      let hasUserInfo = try keychainStore.read(account: "official.baseUserInfo")?.isEmpty == false
      credentialStatus = hasID ? (hasToken && hasUserInfo ? "已保存官方会话" : "已保存账号") : "未保存"
    } catch {
      credentialStatus = "读取失败"
    }
  }

  private func clearCredentials() {
    keychainStore.delete(account: "official.idNumber")
    keychainStore.delete(account: "official.password")
    keychainStore.delete(account: "official.token")
    keychainStore.delete(account: "official.baseUserInfo")
    refreshCredentialStatus()
  }
}
