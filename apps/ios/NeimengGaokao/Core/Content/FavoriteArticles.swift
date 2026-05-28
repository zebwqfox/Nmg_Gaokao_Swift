import Foundation

enum FavoriteArticles {
  private static let key = "favoriteArticleIDs"

  static func contains(_ id: String) -> Bool {
    ids.contains(id)
  }

  static func toggle(_ id: String) -> Bool {
    var current = ids
    if current.contains(id) {
      current.remove(id)
    } else {
      current.insert(id)
    }
    ids = current
    return current.contains(id)
  }

  static var count: Int {
    ids.count
  }

  static func clearAll() {
    ids = []
  }

  private static var ids: Set<String> {
    get {
      Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
    set {
      UserDefaults.standard.set(Array(newValue), forKey: key)
    }
  }
}
