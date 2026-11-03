import SwiftUI

@available(iOS 15.0, *)
final class ChatListStore: ObservableObject {
  @Published private(set) var rows: [ChatRowModel] = []
  @Published private(set) var selecting = false
  @Published private(set) var theme = ChatListTheme.fallback
  @Published private(set) var strings = ChatListStrings.blank
  @Published private(set) var topInset: CGFloat = 0
  @Published private(set) var bottomInset: CGFloat = 0

  func configure(theme: ChatListTheme?, strings: ChatListStrings?, insets: ChatListInsets?) {
    if let theme = theme { self.theme = theme }
    if let strings = strings { self.strings = strings }
    if let insets = insets {
      topInset = CGFloat(insets.top)
      bottomInset = CGFloat(insets.bottom)
    }
  }

  func setTheme(_ theme: ChatListTheme) {
    if self.theme != theme { self.theme = theme }
  }

  func setInsets(_ insets: ChatListInsets) {
    topInset = CGFloat(insets.top)
    bottomInset = CGFloat(insets.bottom)
  }

  func replace(_ payload: ChatListReplace) {
    var seen = Set<String>()
    rows = payload.rows.filter { seen.insert($0.id).inserted }
    selecting = payload.selecting
  }

  func apply(_ diff: ChatListDiff) {
    var byId: [String: ChatRowModel] = [:]
    for row in rows { byId[row.id] = row }
    for id in diff.remove { byId.removeValue(forKey: id) }
    for row in diff.upsert { byId[row.id] = row }
    let order = diff.order ?? rows.map { $0.id }
    var seen = Set<String>()
    let next = order.compactMap { id -> ChatRowModel? in
      guard seen.insert(id).inserted else { return nil }
      return byId[id]
    }
    withAnimation(.easeInOut(duration: 0.25)) {
      rows = next
      selecting = diff.selecting
    }
  }
}
