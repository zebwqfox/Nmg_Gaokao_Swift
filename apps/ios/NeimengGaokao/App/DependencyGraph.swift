import SwiftUI

private struct ContentClientKey: EnvironmentKey {
  static let defaultValue = OfficialContentClient()
}

private struct StudentClientKey: EnvironmentKey {
  static let defaultValue = OfficialStudentClient()
}

private struct KeychainKey: EnvironmentKey {
  static let defaultValue = KeychainStore(service: "app.neimenggaokao.client")
}

extension EnvironmentValues {
  var contentClient: OfficialContentClient {
    get { self[ContentClientKey.self] }
    set { self[ContentClientKey.self] = newValue }
  }

  var studentClient: OfficialStudentClient {
    get { self[StudentClientKey.self] }
    set { self[StudentClientKey.self] = newValue }
  }

  var keychainStore: KeychainStore {
    get { self[KeychainKey.self] }
    set { self[KeychainKey.self] = newValue }
  }
}

extension View {
  func withAppDependencies(
    contentClient: OfficialContentClient = OfficialContentClient(),
    studentClient: OfficialStudentClient = OfficialStudentClient(),
    keychainStore: KeychainStore = KeychainStore(service: "app.neimenggaokao.client")
  ) -> some View {
    environment(\.contentClient, contentClient)
      .environment(\.studentClient, studentClient)
      .environment(\.keychainStore, keychainStore)
  }
}

