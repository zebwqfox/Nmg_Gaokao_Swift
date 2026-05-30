import SwiftUI
import UIKit

/// 全屏图片查看器：支持双指缩放、拖动、双击放大，以及保存/分享。
struct ZoomableImageViewer: View {
  let image: UIImage
  var caption: String = ""

  @Environment(\.dismiss) private var dismiss

  @State private var scale: CGFloat = 1
  @State private var lastScale: CGFloat = 1
  @State private var offset: CGSize = .zero
  @State private var lastOffset: CGSize = .zero

  private let minScale: CGFloat = 1
  private let maxScale: CGFloat = 4

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      Image(uiImage: image)
        .resizable()
        .scaledToFit()
        .scaleEffect(scale)
        .offset(offset)
        .gesture(magnification)
        .simultaneousGesture(dragGesture)
        .onTapGesture(count: 2) { toggleZoom() }

      VStack {
        HStack {
          Spacer()
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.headline)
              .padding(12)
              .background(.ultraThinMaterial, in: Circle())
          }
          .tint(.primary)
          .padding(.trailing, 16)
          .padding(.top, 8)
        }
        Spacer()
        HStack(spacing: 16) {
          ShareLink(item: Image(uiImage: image), preview: SharePreview(caption.isEmpty ? "图片" : caption, image: Image(uiImage: image))) {
            Label("分享", systemImage: "square.and.arrow.up")
          }
          Button {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
          } label: {
            Label("保存", systemImage: "square.and.arrow.down")
          }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .tint(.primary)
        .padding(.bottom, 24)
      }
    }
    .statusBarHidden()
  }

  private var magnification: some Gesture {
    MagnificationGesture()
      .onChanged { value in
        scale = min(max(lastScale * value, minScale), maxScale)
      }
      .onEnded { _ in
        lastScale = scale
        if scale <= minScale { resetOffset() }
      }
  }

  private var dragGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        guard scale > minScale else { return }
        offset = CGSize(
          width: lastOffset.width + value.translation.width,
          height: lastOffset.height + value.translation.height
        )
      }
      .onEnded { _ in
        lastOffset = offset
      }
  }

  private func toggleZoom() {
    withAnimation(.easeOut(duration: 0.25)) {
      if scale > minScale {
        scale = minScale
        lastScale = minScale
        resetOffset()
      } else {
        scale = 2.5
        lastScale = 2.5
      }
    }
  }

  private func resetOffset() {
    offset = .zero
    lastOffset = .zero
  }
}
