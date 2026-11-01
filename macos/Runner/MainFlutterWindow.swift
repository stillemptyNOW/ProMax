import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.setFrameAutosaveName("MainWindow")
    RegisterGeneratedPlugins(registry: flutterViewController)
    ClipboardMediaChannel.register(
      messenger: flutterViewController.engine.binaryMessenger)
    AppIconChannel.register(
      messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

enum AppIconChannel {
  private static let channelName = "io.github.stillemptynow.promax/app_icon"
  private static let canvas: CGFloat = 1024
  private static let body: CGFloat = 824
  private static let radius: CGFloat = 184

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "setAppIcon" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let arguments = call.arguments as? [String: Any]
      guard let data = arguments?["image"] as? FlutterStandardTypedData else {
        NSApplication.shared.applicationIconImage = nil
        result(nil)
        return
      }
      guard let artwork = NSImage(data: data.data) else {
        result(FlutterError(code: "APPLY_FAILED",
                            message: "The icon image could not be decoded",
                            details: nil))
        return
      }
      NSApplication.shared.applicationIconImage = dockIcon(from: artwork)
      result(nil)
    }
  }

  private static func dockIcon(from artwork: NSImage) -> NSImage {
    let size = NSSize(width: AppIconChannel.canvas, height: AppIconChannel.canvas)
    return NSImage(size: size, flipped: false) { rect in
      let inset = (rect.width - AppIconChannel.body) / 2
      let frame = rect.insetBy(dx: inset, dy: inset)
      let corner = AppIconChannel.radius
      NSBezierPath(roundedRect: frame, xRadius: corner, yRadius: corner).addClip()
      artwork.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
      return true
    }
  }
}
