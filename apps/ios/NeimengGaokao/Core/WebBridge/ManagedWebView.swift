import Observation
import SwiftUI
import WebKit

struct ManagedWebView: View {
  let title: String
  let url: URL

  @Environment(\.keychainStore) private var keychainStore
  @State private var state = ManagedWebViewState()

  private var officialToken: String? {
    guard url.host == "www4.nm.zsks.cn" else { return nil }
    return (try? keychainStore.read(account: "official.token")) ?? nil
  }

  private var officialBaseUserInfoJSON: String? {
    guard url.host == "www4.nm.zsks.cn" else { return nil }
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
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .bottomBar) {
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

        Spacer()

        Button {
          state.webView?.reload()
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.glass)

        ShareLink(item: state.webView?.url ?? url) {
          Image(systemName: "square.and.arrow.up")
        }
        .buttonStyle(.glass)
      }
    }
  }
}

@MainActor
@Observable
final class ManagedWebViewState {
  var webView: WKWebView?
  var canGoBack = false
  var canGoForward = false
  var isLoading = true

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
    webView.load(URLRequest(url: url))
    state.update(from: webView)
    return webView
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {
    state.update(from: uiView)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(state: state)
  }

  @MainActor
  final class Coordinator: NSObject, WKNavigationDelegate {
    let state: ManagedWebViewState

    init(state: ManagedWebViewState) {
      self.state = state
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
      state.update(from: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      state.update(from: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      state.update(from: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
      state.update(from: webView)
    }
  }
}
