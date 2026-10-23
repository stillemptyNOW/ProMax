import Flutter
import UIKit

final class ProMaxNativeTabBarFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    return ProMaxNativeTabBarPlatformView(
      frame: frame,
      viewId: viewId,
      args: args as? [String: Any] ?? [:],
      messenger: messenger)
  }
}

private struct ProMaxTabSpec {
  let title: String
  let symbol: String
  let selectedSymbol: String
  let badge: String?
  let avatarKey: String?
  let avatar: Data?

  init(_ map: [String: Any]) {
    title = map["title"] as? String ?? ""
    let symbolName = map["symbol"] as? String ?? "circle"
    symbol = symbolName
    selectedSymbol = map["selectedSymbol"] as? String ?? symbolName
    let rawBadge = map["badge"] as? String
    badge = (rawBadge?.isEmpty ?? true) ? nil : rawBadge
    avatarKey = map["avatarKey"] as? String
    avatar = (map["avatar"] as? FlutterStandardTypedData)?.data
  }
}

final class ProMaxNativeTabBarPlatformView: NSObject, FlutterPlatformView, UITabBarDelegate,
  UIGestureRecognizerDelegate
{
  private static let avatarSide: CGFloat = 28

  private let container: UIView
  private let bar: UITabBar
  private let channel: FlutterMethodChannel
  private var avatarKeys: [String?] = []

  init(frame: CGRect, viewId: Int64, args: [String: Any], messenger: FlutterBinaryMessenger) {
    container = UIView(frame: frame)
    bar = UITabBar(frame: CGRect(origin: .zero, size: frame.size))
    channel = FlutterMethodChannel(
      name: "\(ProMaxNativeGlass.tabBarViewType)/\(viewId)",
      binaryMessenger: messenger)
    super.init()

    container.backgroundColor = .clear
    container.clipsToBounds = false
    bar.frame = container.bounds
    bar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    bar.delegate = self
    bar.clipsToBounds = false
    container.addSubview(bar)

    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
    longPress.minimumPressDuration = 0.45
    longPress.cancelsTouchesInView = false
    longPress.delegate = self
    bar.addGestureRecognizer(longPress)

    applyStyle(args)
    applyItems(args["items"] as? [[String: Any]] ?? [])
    selectIndex((args["selectedIndex"] as? NSNumber)?.intValue ?? 0)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      let arguments = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "setItems":
        self.applyItems(arguments["items"] as? [[String: Any]] ?? [])
        if let index = (arguments["selectedIndex"] as? NSNumber)?.intValue {
          self.selectIndex(index)
        }
        result(nil)
      case "select":
        self.selectIndex((arguments["index"] as? NSNumber)?.intValue ?? 0)
        result(nil)
      case "setStyle":
        self.applyStyle(arguments)
        result(nil)
      case "intrinsicHeight":
        result(Double(self.intrinsicHeight()))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView {
    return container
  }

  private func applyStyle(_ args: [String: Any]) {
    container.overrideUserInterfaceStyle = ProMaxNativeGlass.interfaceStyle(args)
    if let tint = ProMaxNativeGlass.color(args["tint"]) {
      bar.tintColor = tint
    }
  }

  private func applyItems(_ maps: [[String: Any]]) {
    let specs = maps.map(ProMaxTabSpec.init)
    let selected = bar.selectedItem?.tag
    let existing = bar.items ?? []
    if existing.count == specs.count && avatarKeys.count == specs.count {
      for (index, spec) in specs.enumerated() {
        update(existing[index], with: spec, index: index)
      }
      return
    }
    avatarKeys = Array(repeating: nil, count: specs.count)
    var items: [UITabBarItem] = []
    for (index, spec) in specs.enumerated() {
      let item = UITabBarItem(title: spec.title, image: nil, selectedImage: nil)
      item.tag = index
      update(item, with: spec, index: index)
      items.append(item)
    }
    bar.setItems(items, animated: false)
    if let selected = selected, selected >= 0, selected < items.count {
      bar.selectedItem = items[selected]
    }
  }

  private func update(_ item: UITabBarItem, with spec: ProMaxTabSpec, index: Int) {
    if item.title != spec.title {
      item.title = spec.title
    }
    if item.badgeValue != spec.badge {
      item.badgeValue = spec.badge
    }
    let avatar = spec.avatar.flatMap { Self.circularAvatar($0, side: Self.avatarSide) }
    if let avatar = avatar {
      item.image = avatar
      item.selectedImage = avatar
      avatarKeys[index] = spec.avatarKey
      return
    }
    if spec.avatarKey != nil && spec.avatarKey == avatarKeys[index] && item.image != nil {
      return
    }
    avatarKeys[index] = nil
    item.image = Self.symbol(spec.symbol)
    item.selectedImage = Self.symbol(spec.selectedSymbol)
  }

  private func selectIndex(_ index: Int) {
    guard let items = bar.items, index >= 0, index < items.count else { return }
    if bar.selectedItem !== items[index] {
      bar.selectedItem = items[index]
    }
  }

  private func intrinsicHeight() -> CGFloat {
    let width = container.bounds.width > 0 ? container.bounds.width : UIScreen.main.bounds.width
    let fitted = bar.sizeThatFits(
      CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
    return max(0, fitted.height - bar.safeAreaInsets.bottom)
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    let payload: [String: Any] = ["index": item.tag]
    channel.invokeMethod("selected", arguments: payload)
  }

  @objc private func longPressed(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began, let count = bar.items?.count, count > 0 else { return }
    let point = recognizer.location(in: container)
    let width = max(container.bounds.width, 1)
    let index = min(count - 1, max(0, Int(point.x / width * CGFloat(count))))
    let payload: [String: Any] = ["index": index, "x": Double(point.x), "y": Double(point.y)]
    channel.invokeMethod("longPress", arguments: payload)
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    return true
  }

  private static func symbol(_ name: String) -> UIImage? {
    return UIImage(systemName: name) ?? UIImage(systemName: "circle")
  }

  private static func circularAvatar(_ data: Data, side: CGFloat) -> UIImage? {
    guard let source = UIImage(data: data), source.size.width > 0, source.size.height > 0 else {
      return nil
    }
    let size = CGSize(width: side, height: side)
    let scale = max(side / source.size.width, side / source.size.height)
    let drawn = CGSize(width: source.size.width * scale, height: source.size.height * scale)
    let origin = CGPoint(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2)
    let image = UIGraphicsImageRenderer(size: size).image { _ in
      UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
      source.draw(in: CGRect(origin: origin, size: drawn))
    }
    return image.withRenderingMode(.alwaysOriginal)
  }
}
