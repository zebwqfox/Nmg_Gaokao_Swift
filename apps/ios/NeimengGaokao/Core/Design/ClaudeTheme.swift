import SwiftUI

// MARK: - Claude Design System
// Matches claude.ai's warm, minimal aesthetic

enum ClaudeTheme {
  // MARK: Primary palette
  static let primary     = Color(red: 0.851, green: 0.467, blue: 0.341)  // #D97757 terracotta
  static let primarySoft = Color(red: 0.851, green: 0.467, blue: 0.341).opacity(0.12)
  static let primaryMid  = Color(red: 0.851, green: 0.467, blue: 0.341).opacity(0.22)

  // MARK: Surface
  static let surface     = Color(red: 0.980, green: 0.976, blue: 0.965)  // #FAF9F6 warm white
  static let surfaceCard = Color(red: 0.972, green: 0.965, blue: 0.953)  // #F8F6F3
  static let border      = Color(red: 0.898, green: 0.878, blue: 0.847)  // #E5DFD8

  // MARK: Text
  static let textPrimary   = Color(red: 0.102, green: 0.098, blue: 0.090) // #1A1917
  static let textSecondary = Color(red: 0.420, green: 0.396, blue: 0.365) // #6B655D
  static let textTertiary  = Color(red: 0.612, green: 0.584, blue: 0.549) // #9C958C

  // MARK: Status tints
  static let success = Color(red: 0.267, green: 0.588, blue: 0.365)  // #448F5D
  static let info    = Color(red: 0.306, green: 0.514, blue: 0.816)  // #4E83D0
  static let warn    = Color(red: 0.851, green: 0.467, blue: 0.341)  // same as primary
}

// MARK: - View modifiers

extension View {
  /// 标准 Claude 风格卡片（细边框，温暖底色）
  func claudeCard(padding: CGFloat = 16) -> some View {
    self
      .padding(padding)
      .background(ClaudeTheme.surfaceCard)
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(ClaudeTheme.border, lineWidth: 0.75)
      )
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  /// 主色强调卡片（浅橙色背景）
  func claudePrimaryCard(padding: CGFloat = 16) -> some View {
    self
      .padding(padding)
      .background(ClaudeTheme.primarySoft)
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(ClaudeTheme.primary.opacity(0.25), lineWidth: 0.75)
      )
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  /// 输入框风格（白底，细边框，圆角）
  func claudeInputField() -> some View {
    self
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
      .background(Color.white.opacity(0.85))
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(ClaudeTheme.border, lineWidth: 0.75)
      )
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

// MARK: - Button styles

struct ClaudeFilledButtonStyle: ButtonStyle {
  var tint: Color = ClaudeTheme.primary

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 13)
      .background(tint.opacity(configuration.isPressed ? 0.85 : 1))
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
  }
}

struct ClaudeGhostButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.subheadline.weight(.medium))
      .foregroundStyle(ClaudeTheme.primary)
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(configuration.isPressed ? ClaudeTheme.primarySoft : Color.clear)
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(ClaudeTheme.primary.opacity(0.4), lineWidth: 0.75)
      )
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
  }
}

extension ButtonStyle where Self == ClaudeFilledButtonStyle {
  static var claudeFilled: ClaudeFilledButtonStyle { .init() }
}

extension ButtonStyle where Self == ClaudeGhostButtonStyle {
  static var claudeGhost: ClaudeGhostButtonStyle { .init() }
}
