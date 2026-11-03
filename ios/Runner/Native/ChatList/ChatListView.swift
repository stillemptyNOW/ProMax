import SwiftUI

@available(iOS 15.0, *)
typealias ChatListSend = (String, [String]) -> Void

@available(iOS 15.0, *)
struct ChatListView: View {
  @ObservedObject var store: ChatListStore
  let send: ChatListSend

  @State private var revealedInitially = false

  var body: some View {
    ScrollViewReader { proxy in
      List {
        ChatListSearchRow(store: store) { send("search", []) }
          .listRowSeparator(.hidden)
          .listRowBackground(store.theme.surfaceColor)
          .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
        ForEach(store.rows) { row in
          ChatRowView(row: row, store: store)
            .contentShape(Rectangle())
            .onTapGesture {
              send(store.selecting ? "select" : "open", [row.id])
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparatorTint(store.theme.outlineColor)
            .listRowBackground(
              row.selected ? store.theme.primaryColor.opacity(0.1) : store.theme.surfaceColor
            )
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
              Button { send("pin", [row.id]) } label: {
                Label(
                  row.pinned ? store.strings.unpin : store.strings.pin,
                  systemImage: row.pinned ? "pin.slash.fill" : "pin.fill")
              }
              .tint(.orange)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button(role: .destructive) { send("delete", [row.id]) } label: {
                Label(store.strings.delete, systemImage: "trash.fill")
              }
              Button { send("mute", [row.id]) } label: {
                Label(
                  row.muted ? store.strings.unmute : store.strings.mute,
                  systemImage: row.muted ? "bell.fill" : "bell.slash.fill")
              }
              .tint(.indigo)
              Button { send("archive", [row.id]) } label: {
                Label(store.strings.archive, systemImage: "archivebox.fill")
              }
              .tint(.gray)
            }
            .contextMenu {
              Button { send("select", [row.id]) } label: {
                Label(store.strings.select, systemImage: "checkmark.circle")
              }
              Button { send("pin", [row.id]) } label: {
                Label(
                  row.pinned ? store.strings.unpin : store.strings.pin,
                  systemImage: row.pinned ? "pin.slash" : "pin")
              }
              Button { send("mute", [row.id]) } label: {
                Label(
                  row.muted ? store.strings.unmute : store.strings.mute,
                  systemImage: row.muted ? "bell" : "bell.slash")
              }
              Button { send("archive", [row.id]) } label: {
                Label(store.strings.archive, systemImage: "archivebox")
              }
              Button(role: .destructive) { send("delete", [row.id]) } label: {
                Label(store.strings.delete, systemImage: "trash")
              }
            }
        }
        Color.clear
          .frame(height: store.bottomInset)
          .listRowSeparator(.hidden)
          .listRowBackground(store.theme.surfaceColor)
          .listRowInsets(EdgeInsets())
      }
      .listStyle(.plain)
      .chatListTransparentBackground()
      .chatListEdgeEffect()
      .overlay(emptyOverlay)
      .onReceive(store.$rows) { rows in
        guard !revealedInitially, let first = rows.first else { return }
        revealedInitially = true
        DispatchQueue.main.async { proxy.scrollTo(first.id, anchor: .top) }
      }
    }
    .background(store.theme.surfaceColor.ignoresSafeArea())
    .environment(\.colorScheme, store.theme.colorScheme)
    .accentColor(store.theme.primaryColor)
  }

  @ViewBuilder
  private var emptyOverlay: some View {
    if store.rows.isEmpty {
      Text(store.strings.empty)
        .font(.system(size: 16))
        .foregroundColor(store.theme.secondaryColor)
    }
  }
}

@available(iOS 15.0, *)
struct ChatListSearchRow: View {
  @ObservedObject var store: ChatListStore
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
        Text(store.strings.search)
        Spacer()
      }
      .font(.system(size: 16))
      .foregroundColor(store.theme.secondaryColor)
      .padding(.horizontal, 12)
      .frame(height: 38)
      .background(store.theme.secondaryColor.opacity(0.12))
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

@available(iOS 15.0, *)
struct ChatRowView: View {
  let row: ChatRowModel
  @ObservedObject var store: ChatListStore

  private var theme: ChatListTheme { store.theme }

  var body: some View {
    HStack(spacing: 12) {
      if store.selecting {
        Image(systemName: row.selected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 22))
          .foregroundColor(row.selected ? theme.primaryColor : theme.secondaryColor)
          .transition(.move(edge: .leading).combined(with: .opacity))
      }
      AvatarView(url: row.avatarUrl, title: row.title, size: 56)
      VStack(alignment: .leading, spacing: 4) {
        titleLine
        previewLine
      }
    }
    .padding(.vertical, 9)
    .animation(.easeInOut(duration: 0.2), value: store.selecting)
  }

  private var titleLine: some View {
    HStack(spacing: 4) {
      Text(row.title)
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(theme.onSurfaceColor)
        .lineLimit(1)
      if row.verified {
        Image(systemName: "checkmark.seal.fill")
          .font(.system(size: 14))
          .foregroundColor(theme.primaryColor)
      }
      if let badge = row.badge, !badge.isEmpty {
        Text(badge)
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(theme.primaryColor)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(theme.primaryColor.opacity(0.15))
          .clipShape(Capsule())
      }
      if row.muted {
        Image(systemName: "bell.slash.fill")
          .font(.system(size: 12))
          .foregroundColor(theme.secondaryColor)
      }
      if row.pinned {
        Image(systemName: "pin.fill")
          .font(.system(size: 12))
          .foregroundColor(theme.secondaryColor)
      }
      Spacer(minLength: 8)
      if let symbol = statusSymbol {
        Image(systemName: symbol)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(row.ownRead ? theme.primaryColor : theme.secondaryColor)
      }
      Text(row.time)
        .font(.system(size: 14).monospacedDigit())
        .foregroundColor(row.unread > 0 && !row.muted ? theme.primaryColor : theme.secondaryColor)
    }
  }

  private var previewLine: some View {
    HStack(spacing: 6) {
      previewText
        .font(.system(size: 15))
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
      if row.hasCall {
        Image(systemName: "phone.fill")
          .font(.system(size: 12))
          .foregroundColor(.green)
      }
      if row.mention {
        UnreadBadge(text: "@", tint: row.muted ? .gray : theme.primaryColor)
      }
      if row.unread > 0 {
        UnreadBadge(
          text: row.unread > 999 ? "999+" : String(row.unread),
          tint: row.muted ? .gray : theme.primaryColor)
      }
    }
  }

  private var previewText: Text {
    if row.draft {
      return Text(store.strings.draft).foregroundColor(.red)
        + Text(row.preview).foregroundColor(theme.secondaryColor)
    }
    let text = Text(row.preview).foregroundColor(theme.secondaryColor)
    return row.italic ? text.italic() : text
  }

  private var statusSymbol: String? {
    guard let status = row.ownStatus, !row.draft else { return nil }
    switch status {
    case "error": return "exclamationmark.circle.fill"
    case "sending", "pending", "queued": return "clock"
    default: return row.ownRead ? "checkmark.circle.fill" : "checkmark"
    }
  }
}

@available(iOS 15.0, *)
struct UnreadBadge: View {
  let text: String
  let tint: Color

  private var label: some View {
    Text(text)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.white)
      .padding(.horizontal, 7)
      .frame(minWidth: 22, minHeight: 22)
  }

  var body: some View {
    #if compiler(>=6.2)
    if #available(iOS 26.0, *) {
      label.glassEffect(.regular.tint(tint), in: Capsule())
    } else {
      label.background(tint).clipShape(Capsule())
    }
    #else
    label.background(tint).clipShape(Capsule())
    #endif
  }
}

extension View {
  @ViewBuilder
  func chatListTransparentBackground() -> some View {
    if #available(iOS 16.0, *) {
      self.scrollContentBackground(.hidden)
    } else {
      self
    }
  }

  @ViewBuilder
  func chatListEdgeEffect() -> some View {
    #if compiler(>=6.2)
    if #available(iOS 26.0, *) {
      self.scrollEdgeEffectStyle(.soft, for: .all)
    } else {
      self
    }
    #else
    self
    #endif
  }
}
