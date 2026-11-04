import Flutter
import SwiftUI
import UIKit

enum ProMaxNativeUi {
  static let supportChannel = "promax/native_ui_support"
  static let chatListViewType = "promax/native_chat_list"

  static var isSupported: Bool {
    if #available(iOS 15.0, *) {
      return true
    }
    return false
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(
      ProMaxNativeChatListFactory(messenger: registrar.messenger()),
      withId: chatListViewType)
  }

  static func handleSupport(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(isSupported)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

final class ProMaxNativeChatListFactory: NSObject, FlutterPlatformViewFactory {
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
    if #available(iOS 15.0, *) {
      return ProMaxNativeChatListPlatformView(
        frame: frame,
        viewId: viewId,
        args: args as? [String: Any] ?? [:],
        messenger: messenger)
    }
    return ProMaxNativeUnsupportedPlatformView(frame: frame)
  }
}

final class ProMaxNativeUnsupportedPlatformView: NSObject, FlutterPlatformView {
  private let container: UIView

  init(frame: CGRect) {
    container = UIView(frame: frame)
    super.init()
  }

  func view() -> UIView {
    return container
  }
}

@available(iOS 15.0, *)
final class ProMaxNativeChatListPlatformView: NSObject, FlutterPlatformView {
  private let store: ChatListStore
  private let channel: FlutterMethodChannel
  private let hosting: UIHostingController<ChatListView>

  init(frame: CGRect, viewId: Int64, args: [String: Any], messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "\(ProMaxNativeUi.chatListViewType)/\(viewId)",
      binaryMessenger: messenger)
    let store = ChatListStore()
    store.configure(
      theme: ChatListJSON.decode(ChatListTheme.self, from: args["theme"]),
      strings: ChatListJSON.decode(ChatListStrings.self, from: args["strings"]),
      insets: ChatListInsets(
        top: (args["top"] as? NSNumber)?.doubleValue ?? 0,
        bottom: (args["bottom"] as? NSNumber)?.doubleValue ?? 0))
    let send: ChatListSend = { type, ids in
      channel.invokeMethod("action", arguments: ["type": type, "ids": ids])
    }
    self.store = store
    self.channel = channel
    hosting = UIHostingController(rootView: ChatListView(store: store, send: send))
    super.init()
    hosting.view.frame = frame
    hosting.view.backgroundColor = .clear
    hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  func view() -> UIView {
    return hosting.view
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "replace":
      guard let payload = ChatListJSON.decode(ChatListReplace.self, from: call.arguments) else {
        result(FlutterError(code: "bad_args", message: "replace", details: nil))
        return
      }
      store.replace(payload)
      result(nil)
    case "apply":
      guard let diff = ChatListJSON.decode(ChatListDiff.self, from: call.arguments) else {
        result(FlutterError(code: "bad_args", message: "apply", details: nil))
        return
      }
      store.apply(diff)
      result(nil)
    case "theme":
      if let theme = ChatListJSON.decode(ChatListTheme.self, from: call.arguments) {
        store.setTheme(theme)
        hosting.view.backgroundColor = .clear
      }
      result(nil)
    case "insets":
      if let insets = ChatListJSON.decode(ChatListInsets.self, from: call.arguments) {
        store.setInsets(insets)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }
}
