import Observation
import SwiftUI
import WebKit

struct ManagedWebView: View {
  let title: String
  let url: URL

  @Environment(\.keychainStore) private var keychainStore
  @State private var state = ManagedWebViewState()

  private var officialToken: String? {
    guard needsOfficialSession(for: url) else { return nil }
    return (try? keychainStore.read(account: "official.token")) ?? nil
  }

  private var officialBaseUserInfoJSON: String? {
    guard needsOfficialSession(for: url) else { return nil }
    return (try? keychainStore.read(account: "official.baseUserInfo")) ?? nil
  }

  var body: some View {
    ZStack(alignment: .top) {
      WebViewRepresentable(
        url: url,
        token: officialToken,
        baseUserInfoJSON: officialBaseUserInfoJSON,
        state: state
      )
      if state.isLoading {
        ProgressView()
          .controlSize(.small)
          .padding(10)
          .glassEffect(.regular, in: .rect(cornerRadius: 999))
          .padding(.top, 10)
      }
      if let errorMessage = state.errorMessage {
        VStack(spacing: 8) {
          Text(errorMessage)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
          if let retryURL = state.lastFailedURL {
            Button("重试") {
              state.errorMessage = nil
              state.webView?.load(URLRequest(url: retryURL))
            }
            .buttonStyle(.glass)
          }
        }
        .padding()
        .nativeGlassPanel(cornerRadius: 14, tint: .orange.opacity(0.08))
        .padding(.top, 56)
      }
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button {
          state.webView?.goBack()
        } label: {
          Image(systemName: "chevron.backward")
        }
        .disabled(!state.canGoBack)

        Button {
          state.webView?.goForward()
        } label: {
          Image(systemName: "chevron.forward")
        }
        .disabled(!state.canGoForward)

        Button {
          state.webView?.reload()
        } label: {
          Image(systemName: "arrow.clockwise")
        }

        ShareLink(item: state.webView?.url ?? url) {
          Image(systemName: "square.and.arrow.up")
        }
      }
    }
  }

  private func needsOfficialSession(for url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    return host.contains("nm.zsks.cn")
  }
}

@MainActor
@Observable
final class ManagedWebViewState {
  var webView: WKWebView?
  var canGoBack = false
  var canGoForward = false
  var isLoading = true
  var errorMessage: String?
  var lastFailedURL: URL?

  func update(from webView: WKWebView) {
    self.webView = webView
    canGoBack = webView.canGoBack
    canGoForward = webView.canGoForward
    isLoading = webView.isLoading
  }
}

private struct WebViewRepresentable: UIViewRepresentable {
  let url: URL
  let token: String?
  let baseUserInfoJSON: String?
  let state: ManagedWebViewState

  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .default()
    if let script = OfficialWebSessionScript.makeUserScript(token: token, baseUserInfoJSON: baseUserInfoJSON) {
      configuration.userContentController.addUserScript(script)
    }

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.allowsBackForwardNavigationGestures = true
    context.coordinator.load(url, in: webView)
    state.update(from: webView)
    return webView
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {
    state.update(from: uiView)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(
      state: state,
      token: token,
      baseUserInfoJSON: baseUserInfoJSON,
      initialURL: url
    )
  }

  @MainActor
  final class Coordinator: NSObject, WKNavigationDelegate {
    let state: ManagedWebViewState
    let token: String?
    let baseUserInfoJSON: String?
    let initialURL: URL
    private var attemptedURLs = Set<String>()
    private var pendingBootstrapURL: URL?
    private var hasPerformedBootstrap = false

    init(state: ManagedWebViewState, token: String?, baseUserInfoJSON: String?, initialURL: URL) {
      self.state = state
      self.token = token
      self.baseUserInfoJSON = baseUserInfoJSON
      self.initialURL = initialURL
    }

    func load(_ url: URL, in webView: WKWebView) {
      if shouldBootstrap(from: url), !hasPerformedBootstrap {
        hasPerformedBootstrap = true
        pendingBootstrapURL = url
        let home = URL(string: "https://www4.nm.zsks.cn/BaseStudent/Welcome/Index")!
        attemptedURLs.insert(home.absoluteString)
        state.errorMessage = nil
        state.lastFailedURL = home
        webView.load(URLRequest(url: home))
        return
      }
      attemptedURLs.insert(url.absoluteString)
      state.errorMessage = nil
      state.lastFailedURL = url
      webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
      state.update(from: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      injectSession(into: webView)
      bootstrapIfNeeded(on: webView)
      state.errorMessage = nil
      state.update(from: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      handleFailure(error: error, webView: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
      handleFailure(error: error, webView: webView)
    }

    func webView(
      _ webView: WKWebView,
      didReceive challenge: URLAuthenticationChallenge,
      completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
      OfficialSiteTrust.accept(challenge: challenge, completionHandler: completionHandler)
    }

    private func handleFailure(error: Error, webView: WKWebView) {
      state.update(from: webView)
      let nsError = error as NSError
      if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
        return
      }

      let failedURL = webView.url ?? state.lastFailedURL ?? initialURL
      if let alternate = OfficialURLFallback.alternateURL(for: failedURL, excluding: attemptedURLs),
         attemptedURLs.insert(alternate.absoluteString).inserted
      {
        load(alternate, in: webView)
        return
      }

      state.errorMessage = friendlyMessage(for: error)
      state.lastFailedURL = failedURL
    }

    private func injectSession(into webView: WKWebView) {
      guard let source = OfficialWebSessionScript.injectionSource(token: token, baseUserInfoJSON: baseUserInfoJSON) else {
        return
      }
      webView.evaluateJavaScript(source)
    }

    private func bootstrapIfNeeded(on webView: WKWebView) {
      guard let pending = pendingBootstrapURL else { return }
      guard let current = webView.url?.absoluteString, current.contains("/BaseStudent/Welcome/Index") else {
        return
      }
      pendingBootstrapURL = nil
      attemptedURLs.insert(pending.absoluteString)
      state.lastFailedURL = pending
      webView.evaluateJavaScript("window.location.href = \(quoted(pending.absoluteString));")
    }

    private func shouldBootstrap(from url: URL) -> Bool {
      guard url.host == "www4.nm.zsks.cn" else { return false }
      return url.path.contains("/BaseStudent/systemTotal")
    }

    private func quoted(_ value: String) -> String {
      guard let data = try? JSONEncoder().encode(value),
            let json = String(data: data, encoding: .utf8)
      else { return "\"\"" }
      return json
    }

    private func friendlyMessage(for error: Error) -> String {
      let nsError = error as NSError
      if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorSecureConnectionFailed {
        return "官方站点 TLS 证书异常，已尝试 HTTP/HTTPS 切换。请稍后重试。"
      }
      return "页面加载失败：\(error.localizedDescription)"
    }
  }
}
