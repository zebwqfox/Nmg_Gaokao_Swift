import SwiftUI

struct ArticleTableView: View {
  let rows: [[String]]

  private var columnCount: Int {
    rows.map(\.count).max() ?? 0
  }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: true) {
      HStack(alignment: .top, spacing: 0) {
        ForEach(0..<columnCount, id: \.self) { columnIndex in
          VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
              ArticleTableCell(
                text: columnIndex < row.count ? row[columnIndex] : "",
                isHeader: rowIndex == 0,
                isLastColumn: columnIndex == columnCount - 1,
                isLastRow: rowIndex == rows.count - 1,
                minWidth: columnMinWidth(columnIndex)
              )
            }
          }
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 0.5)
    }
    .nativeGlassPanel(cornerRadius: 12, tint: .blue.opacity(0.04))
  }

  private func columnMinWidth(_ columnIndex: Int) -> CGFloat {
    let longest = rows
      .map { columnIndex < $0.count ? $0[columnIndex].count : 0 }
      .max() ?? 0

    switch longest {
    case 0...4:
      return 64
    case 5...8:
      return 80
    case 9...14:
      return 108
    default:
      return 132
    }
  }
}

private struct ArticleTableCell: View {
  let text: String
  let isHeader: Bool
  let isLastColumn: Bool
  let isLastRow: Bool
  let minWidth: CGFloat

  var body: some View {
    Text(displayText)
      .font(isHeader ? .footnote.weight(.semibold) : .footnote)
      .foregroundStyle(text.isEmpty ? .clear : .primary)
      .multilineTextAlignment(.leading)
      .lineLimit(nil)
      .fixedSize(horizontal: false, vertical: true)
      .frame(minWidth: minWidth, maxWidth: 180, minHeight: 36, alignment: .leading)
      .padding(.horizontal, 8)
      .padding(.vertical, 10)
      .background(isHeader ? Color.blue.opacity(0.08) : Color.clear)
      .overlay(alignment: .trailing) {
        if !isLastColumn {
          Rectangle()
            .fill(Color.secondary.opacity(0.22))
            .frame(width: 0.5)
        }
      }
      .overlay(alignment: .bottom) {
        if !isLastRow {
          Rectangle()
            .fill(Color.secondary.opacity(0.22))
            .frame(height: 0.5)
        }
      }
  }

  private var displayText: String {
    text.isEmpty ? " " : text
  }
}
