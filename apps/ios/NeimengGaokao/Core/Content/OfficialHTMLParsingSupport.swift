import Foundation

struct RegexMatch {
  let groups: [String?]

  var fullMatch: String { groups.first.flatMap { $0 } ?? "" }

  subscript(safe index: Int) -> String? {
    guard groups.indices.contains(index) else { return nil }
    return groups[index]
  }
}

extension String {
  var strippingHTML: String {
    replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&#13;", with: "\n")
  }

  var normalizedWhitespace: String {
    replacingOccurrences(of: "[ \\t\\r\\f]+", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "\\n\\s*\\n+", with: "\n\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func matches(of pattern: String) -> [RegexMatch] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
      return []
    }
    let range = NSRange(startIndex..<endIndex, in: self)
    return regex.matches(in: self, range: range).map { result in
      var groups: [String?] = []
      for index in 0..<result.numberOfRanges {
        let nsRange = result.range(at: index)
        guard let range = Range(nsRange, in: self) else {
          groups.append(nil)
          continue
        }
        groups.append(String(self[range]))
      }
      return RegexMatch(groups: groups)
    }
  }

  func firstMatch(of pattern: String) -> RegexMatch? {
    matches(of: pattern).first
  }
}
