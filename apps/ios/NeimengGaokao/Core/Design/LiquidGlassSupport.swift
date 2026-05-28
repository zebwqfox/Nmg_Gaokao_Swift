import SwiftUI

struct NativeGlassGroup<Content: View>: View {
  let spacing: CGFloat
  private let content: Content

  init(spacing: CGFloat = 14, @ViewBuilder content: () -> Content) {
    self.spacing = spacing
    self.content = content()
  }

  var body: some View {
    GlassEffectContainer(spacing: spacing) {
      content
    }
  }
}

extension View {
  @ViewBuilder
  func nativeGlassPanel(
    cornerRadius: CGFloat = 18,
    tint: Color? = nil,
    interactive: Bool = false
  ) -> some View {
    if interactive {
      if let tint {
        self.glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius))
      } else {
        self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
      }
    } else {
      if let tint {
        self.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
      } else {
        self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
      }
    }
  }

  @ViewBuilder
  func nativeGlassButtonStyle(prominent: Bool = false) -> some View {
    if prominent {
      buttonStyle(.glassProminent)
    } else {
      buttonStyle(.glass)
    }
  }
}
