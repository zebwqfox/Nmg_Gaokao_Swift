import SwiftUI
import UIKit

/// 系统分享面板封装，可分享生成的长图等任意内容。
struct ActivityShareSheet: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 让生成的长图能用 `.sheet(item:)` 呈现。
struct ShareableImageItem: Identifiable {
  let id = UUID()
  let image: UIImage
}
