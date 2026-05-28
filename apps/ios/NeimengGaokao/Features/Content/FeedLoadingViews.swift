import SwiftUI

struct FeedLoadMoreFooter: View {
  let isLoading: Bool
  let hasMore: Bool

  var body: some View {
    Group {
      if isLoading {
        HStack(spacing: 10) {
          ProgressView()
            .controlSize(.small)
          Text("加载更多")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
      } else if !hasMore {
        Text("没有更多了")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .transition(.opacity)
      } else {
        EmptyView()
      }
    }
    .animation(.easeInOut(duration: 0.22), value: isLoading)
  }
}

struct FeedInlineLoadingBar: View {
  let message: String

  var body: some View {
    HStack(spacing: 10) {
      ProgressView()
        .controlSize(.small)
      Text(message)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 8)
    .transition(.opacity.combined(with: .move(edge: .top)))
  }
}
