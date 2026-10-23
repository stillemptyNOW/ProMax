import Flutter
import UIKit

enum ProMaxNativeGlass {
  static let glassViewType = "promax/native_glass"
  static let tabBarViewType = "promax/native_tab_bar"
  static let supportChannel = "promax/native_glass_support"

  static var isSupported: Bool {
    #if compiler(>=6.2)
    if #available(iOS 26.0, *) {
      return NSClassFromString("UIGlassEffect") != nil
    }
    #endif
    return false
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    registrar.register(ProMaxNativeGlassFactory(messenger: messenger), withId: glassViewType)
    registrar.register(ProMaxNativeTabBarFactory(messenger: messenger), withId: tabBarViewType)
  }

  static func handleSupport(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(isSupported)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static func color(_ value: Any?) -> UIColor? {
    guard let number = value as? NSNumber else { return nil }
    let argb = UInt32(truncatingIfNeeded: number.int64Value)
    return UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255.0,
      green: CGFloat((argb >> 8) & 0xFF) / 255.0,
      blue: CGFloat(argb & 0xFF) / 255.0,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255.0)
  }

  static func interfaceStyle(_ args: [String: Any]) -> UIUserInterfaceStyle {
    guard let dark = (args["dark"] as? NSNumber)?.boolValue else { return .unspecified }
    return dark ? .dark : .light
  }
}

final class ProMaxNativeGlassFactory: NSObject, FlutterPlatformViewFactory {
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
    return ProMaxNativeGlassPlatformView(
      frame: frame,
      viewId: viewId,
      args: args as? [String: Any] ?? [:],
      messenger: messenger)
  }
}

final class ProMaxGlassContainerView: UIView {
  let effectView = UIVisualEffectView(effect: nil)
  private var radii: [CGFloat] = [0, 0, 0, 0]
  private var usesGlass = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isUserInteractionEnabled = false
    effectView.isUserInteractionEnabled = false
    effectView.frame = bounds
    effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(effectView)
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    effectView.frame = bounds
    applyShape()
  }

  func configure(_ args: [String: Any]) {
    if let values = args["radii"] as? [NSNumber], values.count == 4 {
      radii = values.map { CGFloat(truncating: $0) }
    }
    overrideUserInterfaceStyle = ProMaxNativeGlass.interfaceStyle(args)
    applyEffect(
      clear: (args["style"] as? String) == "clear",
      tint: ProMaxNativeGlass.color(args["tint"]))
    applyShape()
  }

  private func applyEffect(clear: Bool, tint: UIColor?) {
    #if compiler(>=6.2)
    if #available(iOS 26.0, *) {
      let glass = UIGlassEffect(style: clear ? .clear : .regular)
      glass.tintColor = tint
      glass.isInteractive = false
      effectView.effect = glass
      usesGlass = true
      return
    }
    #endif
    effectView.effect = UIBlurEffect(style: .systemThinMaterial)
    effectView.contentView.backgroundColor = tint
    usesGlass = false
  }

  private func applyShape() {
    let limit = max(0, min(bounds.width, bounds.height) / 2)
    let corners = radii.map { min(max($0, 0), limit) }
    effectView.layer.cornerCurve = .continuous
    effectView.clipsToBounds = !usesGlass
    if applyCornerConfiguration(corners) {
      return
    }
    effectView.layer.cornerRadius = corners.max() ?? 0
  }

  private func applyCornerConfiguration(_ corners: [CGFloat]) -> Bool {
    #if compiler(>=6.2)
    if #available(iOS 26.0, *) {
      effectView.cornerConfiguration = .corners(
        topLeftRadius: .fixed(corners[0]),
        topRightRadius: .fixed(corners[1]),
        bottomLeftRadius: .fixed(corners[2]),
        bottomRightRadius: .fixed(corners[3]))
      return true
    }
    #endif
    return false
  }
}

final class ProMaxNativeGlassPlatformView: NSObject, FlutterPlatformView {
  private let container: ProMaxGlassContainerView
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, args: [String: Any], messenger: FlutterBinaryMessenger) {
    container = ProMaxGlassContainerView(frame: frame)
    channel = FlutterMethodChannel(
      name: "\(ProMaxNativeGlass.glassViewType)/\(viewId)",
      binaryMessenger: messenger)
    super.init()
    container.configure(args)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "update":
        self.container.configure(call.arguments as? [String: Any] ?? [:])
        result(nil)
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
}
