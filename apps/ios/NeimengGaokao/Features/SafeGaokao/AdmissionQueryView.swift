import Foundation
import SwiftUI

// MARK: - Result model

struct AdmissionQueryResult {
  let ksh: String
  let name: String
  let school: String
  let major: String
  let batch: String
  let admissionType: String
}

// MARK: - Client

struct AdmissionQueryClient {
  // 专用 session：接受所有 cookie，避免 JSESSIONID 被过滤
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

  private let browserHeaders: [(String, String)] = [
    ("User-Agent",      "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15"),
    ("Accept",          "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"),
    ("Accept-Language", "zh-CN,zh;q=0.9"),
    ("Accept-Encoding", "gzip, deflate"),
    ("Connection",      "keep-alive"),
  ]

  func query(ksh: String, pswd: String) async throws -> (result: AdmissionQueryResult?, debugHTML: String) {
    let session = Self.querySession

    // Step 1: GET 建立 JSESSIONID 会话
    var getReq = URLRequest(url: endpoint)
    browserHeaders.forEach { getReq.setValue($0.1, forHTTPHeaderField: $0.0) }
    _ = try? await session.data(for: getReq)

    // Step 2: POST 查询
    var req = URLRequest(url: endpoint)
    req.httpMethod = "POST"
    browserHeaders.forEach { req.setValue($0.1, forHTTPHeaderField: $0.0) }
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    req.setValue(endpoint.absoluteString, forHTTPHeaderField: "Referer")
    req.setValue("https://www1.nm.zsks.cn", forHTTPHeaderField: "Origin")
    req.httpBody = "v_ksh=\(ksh.percentEncoded)&v_pswd=\(pswd.percentEncoded)".data(using: .utf8)

    let (data, response) = try await session.data(for: req)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw URLError(.badServerResponse)
    }
    let html = String(data: data, encoding: .utf8)
      ?? String(data: data, encoding: .gb18030)
      ?? ""

    return (parseResult(from: html), html)
  }

  private func parseResult(from html: String) -> AdmissionQueryResult? {
    let tablePattern = #"<table[^>]*>(.*?)</table>"#
    let tables = html.matches(of: tablePattern)
    guard let resultTable = tables.first(where: { ($0[safe: 1] ?? "").contains("录取") }) else {
      return nil
    }
    let trPattern = #"<tr[^>]*>(.*?)</tr>"#
    let rows = (resultTable[safe: 1] ?? "").matches(of: trPattern)
    guard rows.count >= 2 else { return nil }

    let headers = extractCells(from: rows[0][safe: 1] ?? "")
    let values  = extractCells(from: rows[1][safe: 1] ?? "")
    guard headers.count == values.count, !values.isEmpty else { return nil }

    var dict: [String: String] = [:]
    zip(headers, values).forEach { dict[$0] = $1 }

    guard let ksh = dict["考生号"], let name = dict["姓名"] else { return nil }
    return AdmissionQueryResult(
      ksh: ksh, name: name,
      school: stripCode(dict["录取院校"] ?? ""),
      major:  stripCode(dict["录取专业"] ?? ""),
      batch:  dict["录取批次"] ?? "",
      admissionType: dict["录取方式"] ?? ""
    )
  }

  private func extractCells(from rowHTML: String) -> [String] {
    rowHTML.matches(of: #"<td[^>]*>(.*?)</td>"#)
      .map { ($0[safe: 1] ?? "").strippingHTML.normalizedWhitespace }
  }

  private func stripCode(_ raw: String) -> String {
    if let r = raw.range(of: #"^[A-Za-z0-9]{1,5}\s+"#, options: .regularExpression) {
      return String(raw[r.upperBound...])
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
  @State private var debugSnippet: String?

  private let client = AdmissionQueryClient()

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        inputSection

        if isQuerying {
          queryingView
        } else if let result {
          resultSection(result)
        } else if notFound {
          notFoundSection
        } else if let error = errorMessage {
          errorSection(error)
        }
      }
      .padding()
    }
    .navigationTitle("录取结果查询")
    .navigationBarTitleDisplayMode(.large)
  }

  // MARK: Input

  private var inputSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("考生信息", systemImage: "person.text.rectangle")
        .font(.headline)

      VStack(spacing: 12) {
        HStack(spacing: 12) {
          Image(systemName: "number")
            .foregroundStyle(.secondary)
            .frame(width: 22)
          TextField("考生号（14位）", text: $ksh)
            .keyboardType(.numberPad)
            .autocorrectionDisabled()
        }
        .padding()
        .nativeGlassPanel(cornerRadius: 12)

        HStack(spacing: 12) {
          Image(systemName: "lock")
            .foregroundStyle(.secondary)
            .frame(width: 22)
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

  // MARK: Querying

  private var queryingView: some View {
    HStack(spacing: 12) {
      ProgressView()
      Text("正在查询，请稍候…")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .nativeGlassPanel(cornerRadius: 16)
  }

  // MARK: Result

  private func resultSection(_ r: AdmissionQueryResult) -> some View {
    VStack(spacing: 0) {
      VStack(spacing: 8) {
        Image(systemName: "checkmark.seal.fill")
          .font(.largeTitle)
          .foregroundStyle(.green)
        Text(r.name)
          .font(.title2.bold())
        Text("已录取")
          .font(.subheadline)
          .foregroundStyle(.green)
        Text(r.ksh)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.tertiary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 20)

      Divider()

      VStack(alignment: .leading, spacing: 0) {
        resultRow(icon: "building.columns.fill", tint: .blue, label: "录取院校", value: r.school)
        Divider().padding(.leading, 36)
        resultRow(icon: "graduationcap.fill", tint: .purple, label: "录取专业", value: r.major)
        Divider().padding(.leading, 36)
        resultRow(icon: "tray.and.arrow.down.fill", tint: .orange, label: "录取批次", value: r.batch)
        Divider().padding(.leading, 36)
        resultRow(icon: "checkmark.circle.fill", tint: .green, label: "录取方式", value: r.admissionType)
      }
      .padding()
    }
    .nativeGlassPanel(cornerRadius: 18, tint: .green.opacity(0.06))
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
        Text(value.isEmpty ? "—" : value)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
      }
      Spacer()
    }
    .padding(.vertical, 12)
  }

  // MARK: Not found

  private var notFoundSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        Image(systemName: "person.fill.questionmark")
          .font(.title3)
          .foregroundStyle(.orange)
        Text("未查到录取信息")
          .font(.headline)
      }
      Text("请确认考生号和密码是否正确，录取信息可能尚未更新。")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      if let snippet = debugSnippet, !snippet.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text("服务器响应（调试）")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          ScrollView {
            Text(snippet)
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxHeight: 180)
        }
        .padding(10)
        .nativeGlassPanel(cornerRadius: 10, tint: .orange.opacity(0.06))
      }
    }
    .padding()
    .nativeGlassPanel(cornerRadius: 18, tint: .orange.opacity(0.05))
  }

  // MARK: Error

  private func errorSection(_ message: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(.orange)
      VStack(alignment: .leading, spacing: 4) {
        Text("查询失败")
          .font(.headline)
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .nativeGlassPanel(cornerRadius: 18, tint: .orange.opacity(0.06))
  }

  // MARK: Submit

  private func submit() async {
    guard !isQuerying else { return }
    isQuerying = true
    result = nil
    notFound = false
    errorMessage = nil
    debugSnippet = nil
    defer { isQuerying = false }
    do {
      let (r, html) = try await client.query(ksh: ksh, pswd: pswd)
      if let r {
        result = r
      } else {
        notFound = true
        debugSnippet = String(html.prefix(800))
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
