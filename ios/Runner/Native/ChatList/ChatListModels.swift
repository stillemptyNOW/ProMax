import SwiftUI

struct ChatRowModel: Codable, Identifiable, Equatable {
  let id: String
  let title: String
  let preview: String
  let time: String
  let avatarUrl: String
  let kind: String
  let unread: Int
  let mention: Bool
  let muted: Bool
  let pinned: Bool
  let verified: Bool
  let selected: Bool
  let draft: Bool
  let italic: Bool
  let ownStatus: String?
  let ownRead: Bool
  let hasCall: Bool
  let badge: String?
}

struct ChatListReplace: Decodable {
  let rows: [ChatRowModel]
  let selecting: Bool
}

struct ChatListDiff: Decodable {
  let order: [String]?
  let upsert: [ChatRowModel]
  let remove: [String]
  let selecting: Bool
}

struct ChatListInsets: Decodable {
  let top: Double
  let bottom: Double
}

struct ChatListTheme: Decodable, Equatable {
  let dark: Bool
  let primary: Int
  let surface: Int
  let onSurface: Int
  let onSurfaceVariant: Int
  let outline: Int

  static let fallback = ChatListTheme(
    dark: false,
    primary: 0xFF3D7BF7,
    surface: 0xFFFFFFFF,
    onSurface: 0xFF000000,
    onSurfaceVariant: 0xFF6B6B70,
    outline: 0x33000000)

  static func color(_ argb: Int) -> Color {
    let value = UInt32(truncatingIfNeeded: argb)
    return Color(
      .sRGB,
      red: Double((value >> 16) & 0xFF) / 255.0,
      green: Double((value >> 8) & 0xFF) / 255.0,
      blue: Double(value & 0xFF) / 255.0,
      opacity: Double((value >> 24) & 0xFF) / 255.0)
  }

  var primaryColor: Color { Self.color(primary) }
  var surfaceColor: Color { Self.color(surface) }
  var onSurfaceColor: Color { Self.color(onSurface) }
  var secondaryColor: Color { Self.color(onSurfaceVariant) }
  var outlineColor: Color { Self.color(outline) }
  var colorScheme: ColorScheme { dark ? .dark : .light }
}

struct ChatListStrings: Decodable, Equatable {
  let pin: String
  let unpin: String
  let mute: String
  let unmute: String
  let archive: String
  let delete: String
  let select: String
  let search: String
  let empty: String
  let draft: String

  static let blank = ChatListStrings(
    pin: "", unpin: "", mute: "", unmute: "", archive: "", delete: "",
    select: "", search: "", empty: "", draft: "")
}

enum ChatListJSON {
  static func decode<T: Decodable>(_ type: T.Type, from object: Any?) -> T? {
    guard let object = object, JSONSerialization.isValidJSONObject(object),
      let data = try? JSONSerialization.data(withJSONObject: object)
    else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
  }
}
