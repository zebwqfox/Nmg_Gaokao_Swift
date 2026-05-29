import Foundation
import SwiftUI

// MARK: - Result model

struct AdmissionQueryResult {
  let ksh: String
  let name: String
  let school: String       // 录取院校（去掉院校代码前缀）
  let major: String        // 录取专业（去掉专业代码前缀）
  let batch: String        // 录取批次
  let admissionType: String // 录取方式
}

// MARK: - Client

struct AdmissionQueryClient {
  // 专用 session：接受所有 cookie，避免 .onlyFromMainDocumentDomain 过滤掉 JSESSIONID
  private static let querySession: URLSession = {
    let config = URLSessionConfiguration.default
    config.httpCookieAcceptPolicy = .always
    config.httpShouldSetCookies = true
    config.timeoutIntervalForRequest = 25
    config.timeoutIntervalForResource = 45
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.urlCache = nil
    return URLSession(configuration: config,
                      delegate: OfficialSiteTrust.makeSessionDelegate(),
                      delegateQueue: nil)
  }()

  private let endpoint = URL(string: "https://www1.nm.zsks.cn/Gkcjcx/kslqjgcx25_qcsj.jsp")!

  private let headers: [(String, String)] = [
    ("User-Agent",      "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15"),
    ("Accept",          "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"),
    ("Accept-Language", "zh-CN,zh;q=0.9"),
    ("Accept-Encoding", "gzip, deflate"),
    ("Connection",      "keep-alive"),
  ]

  func query(ksh: String, pswd: String) async throws -> (result: AdmissionQueryResult?, debugHTML: String) {
    let session = Self.querySession

    // Step 1: GET — 服务器发放 JSESSIONID cookie
    var getReq = URLRequest(url: endpoint)
    headers.forEach { getReq.setValue($0.1, forHTTPHeaderField: $0.0) }
    _ = try? await session.data(for: getReq)

    // Step 2: POST — cookie 自动携带，body 仅含考生号和密码
    var req = URLRequest(url: endpoint)
    req.httpMethod = "POST"
    headers.forEach { req.setValue($0.1, forHTTPHeaderField: $0.0) }
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    req.setValue(endpoint.absoluteString, forHTTPHeaderField: "Referer")
    req.setValue("https://www1.nm.zsks.cn", forHTTPHeaderField: "Origin")

    // 不发 query= 参数（浏览器 form.submit() 也不发）
    let body = "v_ksh=\(ksh.percentEncoded)&v_pswd=\(pswd.percentEncoded)"
    req.httpBody = body.data(using: .utf8)

    let (data, response) = try await session.data(for: req)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw URLError(.badServerResponse)
    }
    let html = String(data: data, encoding: .utf8)
      ?? String(data: data, encoding: .gb18030)
      ?? ""

    return (parseResult(from: html), html)
  }

  // 解析结果：跳过表单 table，找第二张有 border="1" 的结果表
  // 第一行 td 是表头，第二行 td 是数据
  private func parseResult(from html: String) -> AdmissionQueryResult? {
    // 提取所有 <table>…</table> 块
    let tablePattern = #"<table[^>]*>(.*?)</table>"#
    let tables = html.matches(of: tablePattern)

    // 找第一张含「录取」内容的表
    guard let resultTable = tables.first(where: { ($0[safe: 1] ?? "").contains("录取") }) else {
      return nil
    }
    let tableHTML = resultTable[safe: 1] ?? ""

    // 提取所有 <tr>
    let trPattern = #"<tr[^>]*>(.*?)</tr>"#
    let rows = tableHTML.matches(of: trPattern)
    guard rows.count >= 2 else { return nil }

    // 第一行 = 表头
    let headers = extractCells(from: rows[0][safe: 1] ?? "")
    // 第二行 = 数据
    let values = extractCells(from: rows[1][safe: 1] ?? "")
    guard headers.count == values.count, !values.isEmpty else { return nil }

    // 建立 header→value 字典
    var dict: [String: String] = [:]
    for (h, v) in zip(headers, values) {
      dict[h] = v
    }

    guard let ksh = dict["考生号"], let name = dict["姓名"] else { return nil }

    return AdmissionQueryResult(
      ksh: ksh,
      name: name,
      school: stripCode(dict["录取院校"] ?? ""),
      major: stripCode(dict["录取专业"] ?? ""),
      batch: dict["录取批次"] ?? "",
      admissionType: dict["录取方式"] ?? ""
    )
  }

  private func extractCells(from rowHTML: String) -> [String] {
    let tdPattern = #"<td[^>]*>(.*?)</td>"#
    return rowHTML.matches(of: tdPattern).map { m in
      (m[safe: 1] ?? "").strippingHTML.normalizedWhitespace
    }
  }

  // 去掉 "473 " / "1H " 这类院校/专业代码前缀
  private func stripCode(_ raw: String) -> String {
    let pattern = #"^[A-Za-z0-9]{1,5}\s+"#
    if let range = raw.range(of: pattern, options: .regularExpression) {
      return String(raw[range.upperBound...])
    }
    return raw
  }
}

private extension String {
  var percentEncoded: String {
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
  @State private var notFound = false
  @State private var errorMessage: String?
  @State private var debugSnippet: String?   // 解析失败时显示响应片段

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
        } else if notFound {
          VStack(spacing: 16) {
            ContentUnavailableView(
              "未查到录取信息",
              systemImage: "person.fill.questionmark",
              description: Text("请确认考生号和密码是否正确，或暂未录取。")
            )
            if let snippet = debugSnippet {
              VStack(alignment: .leading, spacing: 8) {
                Text("服务器返回内容（调试）")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)
                ScrollView {
                  Text(snippet)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
              }
              .padding()
              .nativeGlassPanel(cornerRadius: 12, tint: .orange.opacity(0.08))
            }
          }
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

  // MARK: Input card

  private var inputCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("考生信息", systemImage: "person.text.rectangle")
        .font(.headline)

      VStack(spacing: 10) {
        HStack(spacing: 12) {
          Image(systemName: "number")
            .foregroundStyle(.secondary)
            .frame(width: 20)
          TextField("考生号（14位）", text: $ksh)
            .keyboardType(.numberPad)
            .autocorrectionDisabled()
        }
        .padding()
        .nativeGlassPanel(cornerRadius: 12)

        HStack(spacing: 12) {
          Image(systemName: "lock")
            .foregroundStyle(.secondary)
            .frame(width: 20)
          SecureField("密码", text: $pswd)
        }
        .padding()
        .nativeGlassPanel(cornerRadius: 12)
      }

      Button {
        Task { await submit() }
      } label: {
        HStack(spacing: 8) {
          if isQuerying { ProgressView().controlSize(.small) }
          Text(isQuerying ? "查询中…" : "查询录取结果")
            .font(.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.glassProminent)
      .disabled(isQuerying || ksh.count < 14 || pswd.isEmpty)

      Text("密码通常为身份证后6位，具体以官方说明为准。")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding()
    .nativeGlassPanel(cornerRadius: 18, tint: .blue.opacity(0.06))
  }

  // MARK: Result card

  private func resultCard(_ r: AdmissionQueryResult) -> some View {
    VStack(spacing: 0) {
      // 姓名 banner
      VStack(spacing: 4) {
        Image(systemName: "checkmark.seal.fill")
          .font(.largeTitle)
          .foregroundStyle(.green)
        Text(r.name)
          .font(.title2.bold())
        Text("已录取")
          .font(.subheadline)
          .foregroundStyle(.green)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 20)

      Divider()

      // 录取院校 + 专业（突出显示）
      VStack(alignment: .leading, spacing: 8) {
        resultRow(icon: "building.columns.fill", tint: .blue,
                  label: "录取院校", value: r.school)
        Divider().padding(.leading, 36)
        resultRow(icon: "graduationcap.fill", tint: .purple,
                  label: "录取专业", value: r.major)
        Divider().padding(.leading, 36)
        resultRow(icon: "list.bullet.clipboard.fill", tint: .orange,
                  label: "录取批次", value: r.batch)
        Divider().padding(.leading, 36)
        resultRow(icon: "checkmark.circle.fill", tint: .green,
                  label: "录取方式", value: r.admissionType)
      }
      .padding()
    }
    .nativeGlassPanel(cornerRadius: 18, tint: .green.opacity(0.05))
  }

  private func resultRow(icon: String, tint: Color, label: String, value: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon)
        .foregroundStyle(tint)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 2) {
        Text(label)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(value)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
      }
    }
  }

  // MARK: Submit

  private func submit() async {
    guard !isQuerying else { return }
    isQuerying = true
    result = nil
    notFound = false
    errorMessage = nil
    defer { isQuerying = false }
    do {
      let (r, html) = try await client.query(ksh: ksh, pswd: pswd)
      if let r {
        result = r
        debugSnippet = nil
      } else {
        notFound = true
        // 取前 800 字符供调试
        debugSnippet = String(html.prefix(800))
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
