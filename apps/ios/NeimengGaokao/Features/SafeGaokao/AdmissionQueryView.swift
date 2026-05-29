import SwiftUI

// MARK: - Query result model

struct AdmissionQueryResult {
  let rows: [(label: String, value: String)]  // 解析出的键值对
  let rawHTML: String                          // 保留原始 HTML 供 fallback
}

// MARK: - Client

struct AdmissionQueryClient {
  var session: URLSession = OfficialSiteTrust.makeSession()

  private let endpoint = URL(string: "https://www1.nm.zsks.cn/Gkcjcx/kslqjgcx25_qcsj.jsp")!

  func query(ksh: String, pswd: String) async throws -> AdmissionQueryResult {
    var req = URLRequest(url: endpoint)
    req.httpMethod = "POST"
    req.timeoutInterval = 20
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15",
                 forHTTPHeaderField: "User-Agent")
    req.setValue("https://www1.nm.zsks.cn/", forHTTPHeaderField: "Referer")

    let body = "v_ksh=\(ksh.urlEncoded)&v_pswd=\(pswd.urlEncoded)&query=%E6%9F%A5+%E8%AF%A2"
    req.httpBody = body.data(using: .utf8)

    let (data, response) = try await session.data(for: req)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw URLError(.badServerResponse)
    }
    let html = String(data: data, encoding: .utf8)
      ?? String(data: data, encoding: .gb18030)
      ?? ""

    return AdmissionQueryResult(rows: parseResultRows(from: html), rawHTML: html)
  }

  // 从响应 HTML 中提取键值对（td:th 或 label:value 模式）
  private func parseResultRows(from html: String) -> [(label: String, value: String)] {
    var rows: [(String, String)] = []

    // 匹配 <th>xxx</th><td>yyy</td> 或 <td class=...>xxx</td><td>yyy</td>
    let thTdPattern = #"<th[^>]*>(.*?)</th>\s*<td[^>]*>(.*?)</td>"#
    for m in html.matches(of: thTdPattern) {
      let label = (m[safe: 1] ?? "").strippingHTML.normalizedWhitespace
      let value = (m[safe: 2] ?? "").strippingHTML.normalizedWhitespace
      if !label.isEmpty, !value.isEmpty {
        rows.append((label, value))
      }
    }

    // 如果 th/td 没匹配到，尝试连续两个 td 的 label:value 模式
    if rows.isEmpty {
      let tdPattern = #"<td[^>]*>\s*([^<]{2,20}[：:])\s*</td>\s*<td[^>]*>(.*?)</td>"#
      for m in html.matches(of: tdPattern) {
        let label = (m[safe: 1] ?? "").strippingHTML.normalizedWhitespace
          .trimmingCharacters(in: CharacterSet(charactersIn: "：:"))
        let value = (m[safe: 2] ?? "").strippingHTML.normalizedWhitespace
        if !label.isEmpty, !value.isEmpty {
          rows.append((label, value))
        }
      }
    }

    // 提取可能的提示/错误信息
    if rows.isEmpty {
      let msgPattern = #"<(?:p|div|span|td)[^>]*>\s*([^<]{6,100})\s*</(?:p|div|span|td)>"#
      for m in html.matches(of: msgPattern) {
        let text = (m[safe: 1] ?? "").strippingHTML.normalizedWhitespace
        let lower = text.lowercased()
        if lower.contains("查询") || lower.contains("录取") || lower.contains("未查") || lower.contains("错误") {
          rows.append(("提示", text))
          break
        }
      }
    }

    return rows
  }
}

private extension String {
  var urlEncoded: String {
    addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
  }
}

// MARK: - View

struct AdmissionQueryView: View {
  @Environment(RouterPath.self) private var router

  @State private var ksh = ""
  @State private var pswd = ""
  @State private var isQuerying = false
  @State private var result: AdmissionQueryResult?
  @State private var errorMessage: String?

  private let client = AdmissionQueryClient()

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        inputCard
        if isQuerying {
          ProgressView("正在查询")
            .frame(maxWidth: .infinity, minHeight: 80)
        } else if let result {
          resultCard(result)
        } else if let error = errorMessage {
          ContentUnavailableView(
            "查询失败",
            systemImage: "wifi.exclamationmark",
            description: Text(error)
          )
        }
      }
      .padding()
    }
    .navigationTitle("录取结果查询")
    .navigationBarTitleDisplayMode(.large)
  }

  // MARK: Input

  private var inputCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("考生信息", systemImage: "person.text.rectangle")
        .font(.headline)

      VStack(spacing: 12) {
        HStack {
          Image(systemName: "number")
            .foregroundStyle(.secondary)
            .frame(width: 24)
          TextField("考生号（14位）", text: $ksh)
            .keyboardType(.numberPad)
            .autocorrectionDisabled()
        }
        .padding()
        .nativeGlassPanel(cornerRadius: 12)

        HStack {
          Image(systemName: "lock")
            .foregroundStyle(.secondary)
            .frame(width: 24)
          SecureField("密码", text: $pswd)
        }
        .padding()
        .nativeGlassPanel(cornerRadius: 12)
      }

      Button {
        Task { await submit() }
      } label: {
        HStack {
          if isQuerying { ProgressView().controlSize(.small) }
          Text(isQuerying ? "查询中…" : "查询录取结果")
            .font(.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.glassProminent)
      .disabled(isQuerying || ksh.count < 14 || pswd.isEmpty)

      Text("密码通常为身份证后6位或准考证后6位，具体以官方说明为准。")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding()
    .nativeGlassPanel(cornerRadius: 18, tint: .blue.opacity(0.06))
  }

  // MARK: Result

  private func resultCard(_ result: AdmissionQueryResult) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if result.rows.isEmpty {
        // 解析不到结构化数据 → fallback 按钮
        VStack(spacing: 12) {
          Image(systemName: "exclamationmark.triangle")
            .font(.largeTitle)
            .foregroundStyle(.orange)
          Text("结果已返回，但无法解析为结构化内容。")
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
          Button {
            let url = URL(string: "https://www1.nm.zsks.cn/Gkcjcx/kslqjgcx25_qcsj.jsp")!
            router.navigate(to: .web(title: "录取结果查询", url: url))
          } label: {
            Label("在网页中查看", systemImage: "safari")
          }
          .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity)
        .padding()
      } else {
        ForEach(Array(result.rows.enumerated()), id: \.offset) { idx, row in
          HStack(alignment: .top, spacing: 12) {
            Text(row.label)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .frame(width: 90, alignment: .trailing)
            Text(row.value)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .padding(.vertical, 10)
          .padding(.horizontal)
          if idx < result.rows.count - 1 { Divider().padding(.leading) }
        }
      }
    }
    .nativeGlassPanel(cornerRadius: 18, tint: .green.opacity(0.05))
  }

  // MARK: Submit

  private func submit() async {
    guard !isQuerying else { return }
    isQuerying = true
    errorMessage = nil
    result = nil
    defer { isQuerying = false }
    do {
      result = try await client.query(ksh: ksh, pswd: pswd)
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
