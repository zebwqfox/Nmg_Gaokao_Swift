import SwiftUI

struct ArticleTableView: View {
  let rows: [[String]]

  private var columnCount: Int {
    rows.map(\.count).max() ?? 0
  }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: true) {
      Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
        ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
          GridRow {
            ForEach(0..<columnCount, id: \.self) { columnIndex in
              let cell = columnIndex < row.count ? row[columnIndex] : ""
              Text(cell)
                .font(rowIndex == 0 ? .footnote.weight(.semibold) : .footnote)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(minWidth: 76, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .background(rowIndex == 0 ? Color.blue.opacity(0.08) : Color.clear)
                .overlay {
                  Rectangle()
                    .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 0.5)
                }
            }
          }
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .nativeGlassPanel(cornerRadius: 12, tint: .blue.opacity(0.04))
  }
}
