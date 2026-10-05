import Flutter
import UIKit
import UserNotifications

final class ProMaxNotifications: NSObject {
  static let shared = ProMaxNotifications()

  private static let chatKeys = ["promax_chat", "chatId", "chat_id"]

  private var sink: FlutterEventSink?
  private var pendingChatId: Int64 = 0
  private var activeChatId: Int64 = 0
  private var pushResult: FlutterResult?
  private var pushTimeout: Timer?
  private var pushToken: String?

  func start() {
    UNUserNotificationCenter.current().delegate = self
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pushCapabilities":
      result(pushCapabilities())
    case "registerNativePush":
      registerNativePush(result)
    case "testLocalNotification":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        DispatchQueue.main.async {
          guard granted else {
            result(FlutterError(code: "PERMISSION_DENIED", message: "Уведомления запрещены в настройках iPhone", details: nil))
            return
          }
          let content = UNMutableNotificationContent()
          content.title = "ProMax"
          content.body = "Локальные уведомления разрешены. Для фоновых сообщений подключите доставку push."
          content.sound = .default
          let request = UNNotificationRequest(identifier: "promax-test", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))
          UNUserNotificationCenter.current().add(request) { error in
            DispatchQueue.main.async {
              if let error = error { result(FlutterError(code: "LOCAL_FAILED", message: error.localizedDescription, details: nil)) }
              else { result(nil) }
            }
          }
        }
      }
    case "consumeInitialChat":
      let chatId = pendingChatId
      pendingChatId = 0
      result(chatId != 0 ? NSNumber(value: chatId) : nil)
    case "setActiveChat":
      activeChatId = Self.chatId(from: call.arguments)
      dismissDelivered(chatId: activeChatId)
      result(nil)
    case "clearActiveChat":
      activeChatId = 0
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func pushCapabilities() -> [String: Any] {
    var info: [String: Any] = ["profileFound": false, "bundleMatches": false, "apsEnvironment": "", "expired": false]
    guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
          let bytes = try? Data(contentsOf: url), bytes.count < 4 * 1024 * 1024,
          let start = bytes.range(of: Data("<plist".utf8)),
          let end = bytes.range(of: Data("</plist>".utf8), in: start.lowerBound..<bytes.endIndex),
          let profile = (try? PropertyListSerialization.propertyList(from: bytes.subdata(in: start.lowerBound..<end.upperBound), format: nil)) as? [String: Any],
          let entitlements = profile["Entitlements"] as? [String: Any] else { return info }
    info["profileFound"] = true
    info["apsEnvironment"] = entitlements["aps-environment"] as? String ?? ""
    let appId = entitlements["application-identifier"] as? String ?? ""
    let bundle = Bundle.main.bundleIdentifier ?? ""
    info["bundleMatches"] = !bundle.isEmpty && appId.hasSuffix(".\(bundle)")
    if let expiration = profile["ExpirationDate"] as? Date { info["expired"] = expiration < Date() }
    return info
  }

  func attach(_ sink: FlutterEventSink?) {
    self.sink = sink
  }

  func deliver(chatId: Int64) {
    guard chatId != 0 else { return }
    if let sink = sink {
      sink(NSNumber(value: chatId))
    } else {
      pendingChatId = chatId
    }
  }

  private func dismissDelivered(chatId: Int64) {
    guard chatId != 0 else { return }
    let center = UNUserNotificationCenter.current()
    center.getDeliveredNotifications { delivered in
      let identifiers = delivered
        .filter { Self.chatId(from: $0.request.content.userInfo) == chatId }
        .map { $0.request.identifier }
      guard !identifiers.isEmpty else { return }
      center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
  }

  private func registerNativePush(_ result: @escaping FlutterResult) {
    guard pushResult == nil else {
      result(FlutterError(code: "BUSY", message: "Регистрация в APNs уже выполняется", details: nil))
      return
    }
    pushResult = result
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      DispatchQueue.main.async {
        guard granted else {
          self.finishPushRegistration(FlutterError(code: "PERMISSION_DENIED", message: "Уведомления запрещены в настройках iPhone", details: nil))
          return
        }
        self.pushTimeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { _ in
          self.finishPushRegistration(FlutterError(code: "APNS_TIMEOUT", message: "Apple не ответила вовремя. Проверьте интернет и профиль подписи.", details: nil))
        }
        UIApplication.shared.registerForRemoteNotifications()
      }
    }
  }

  func registeredForPush(_ deviceToken: Data) {
    pushToken = deviceToken.map { String(format: "%02x", $0) }.joined()
    finishPushRegistration(pushToken)
  }

  func failedPushRegistration(_ error: Error) {
    pushToken = nil
    finishPushRegistration(FlutterError(code: "APNS_REGISTRATION_FAILED", message: error.localizedDescription, details: nil))
  }

  private func finishPushRegistration(_ value: Any?) {
    pushTimeout?.invalidate()
    pushTimeout = nil
    let result = pushResult
    pushResult = nil
    result?(value)
  }

  private static func chatId(from raw: Any?) -> Int64 {
    if let number = raw as? NSNumber { return number.int64Value }
    if let text = raw as? String { return Int64(text) ?? 0 }
    if let map = raw as? [AnyHashable: Any] {
      for key in chatKeys {
        if let value = map[key], let parsed = optionalChatId(value) { return parsed }
      }
    }
    return 0
  }

  private static func optionalChatId(_ raw: Any) -> Int64? {
    if let number = raw as? NSNumber { return number.int64Value }
    if let text = raw as? String { return Int64(text) }
    return nil
  }
}

extension ProMaxNotifications: UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let chatId = Self.chatId(from: notification.request.content.userInfo)
    if chatId != 0, chatId == activeChatId {
      completionHandler([])
      return
    }
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    deliver(chatId: Self.chatId(from: response.notification.request.content.userInfo))
    completionHandler()
  }
}
