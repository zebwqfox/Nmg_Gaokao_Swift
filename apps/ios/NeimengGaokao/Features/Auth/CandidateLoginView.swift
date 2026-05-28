import SwiftData
import SwiftUI

struct CandidateLoginView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.studentClient) private var studentClient
  @Environment(\.keychainStore) private var keychainStore
  @Environment(\.modelContext) private var modelContext

  @Query private var candidates: [CandidateProfile]

  @State private var idNumber = ""
  @State private var password = ""
  @State private var captchaInput = ""
  @State private var captchaCode = ""
  @State private var statusText: String?
  @State private var isSubmitting = false

  var body: some View {
    Form {
      Section("官方账号") {
        TextField("准考证号或证件号", text: $idNumber)
          .textInputAutocapitalization(.characters)
          .autocorrectionDisabled()
        SecureField("密码", text: $password)
        HStack {
          TextField("验证码", text: $captchaInput)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          Spacer()
          Button {
            refreshCaptcha()
          } label: {
            Text(captchaCode.isEmpty ? "刷新" : captchaCode)
              .font(.headline.monospaced())
              .frame(minWidth: 76)
              .padding(.vertical, 8)
              .nativeGlassPanel(cornerRadius: 12, tint: .blue.opacity(0.08), interactive: true)
          }
          .buttonStyle(.plain)
        }
      }

      Section {
        Button {
          Task { await submit() }
        } label: {
          HStack {
            if isSubmitting {
              ProgressView()
            }
            Text(isSubmitting ? "正在登录" : "登录并绑定")
          }
        }
        .buttonStyle(.glassProminent)
        .disabled(isSubmitting || idNumber.isEmpty || password.isEmpty || captchaInput.isEmpty)

        if let statusText {
          Text(statusText)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      } footer: {
        Text("验证码在 App 内本地生成并校验。密码只通过官方接口登录，保存到 Keychain 仅用于之后自动进入官方办事页。")
      }
    }
    .navigationTitle("绑定考生")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if captchaCode.isEmpty {
        refreshCaptcha()
      }
    }
  }

  private func refreshCaptcha() {
    captchaCode = studentClient.makeCaptcha()
    captchaInput = ""
  }

  private func submit() async {
    guard captchaInput.caseInsensitiveCompare(captchaCode) == .orderedSame else {
      statusText = "验证码不正确，请重新输入。"
      refreshCaptcha()
      return
    }

    isSubmitting = true
    statusText = nil
    defer { isSubmitting = false }

    do {
      let response = try await studentClient.login(idNumber: idNumber, password: password, captcha: captchaInput)
      guard response.success == true || response.code == 200 else {
        statusText = response.displayMessage
        refreshCaptcha()
        return
      }

      try keychainStore.save(idNumber, account: "official.idNumber")
      try keychainStore.save(password, account: "official.password")
      guard let token = response.data?.token, !token.isEmpty else {
        statusText = "官方接口未返回登录令牌，请稍后重试。"
        refreshCaptcha()
        return
      }
      try keychainStore.save(token, account: "official.token")
      if let baseUserInfo = response.data?.storageJSONString {
        try keychainStore.save(baseUserInfo, account: "official.baseUserInfo")
      }

      let last4 = String(idNumber.suffix(4))
      if candidates.isEmpty {
        modelContext.insert(CandidateProfile(displayName: "内蒙古考生", idNumberLast4: last4, examType: "高考"))
      }
      try? modelContext.save()
      dismiss()
    } catch {
      statusText = "登录失败：\(error.localizedDescription)"
      refreshCaptcha()
    }
  }
}
