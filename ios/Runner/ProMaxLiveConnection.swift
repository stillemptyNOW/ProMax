import AVFoundation
import Flutter
import UIKit
import UserNotifications

final class ProMaxLiveConnection: NSObject {
  static let shared = ProMaxLiveConnection()

  private let enabledKey = "promax_live_connection"
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var observers: [NSObjectProtocol] = []
  private var started = false

  var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

  func start() {
    guard !started else { return }
    started = true
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
      self?.syncKeepAlive()
    })
    observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
      self?.stopKeepAlive()
    })
    observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
      guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
      self?.restartIfNeeded()
    })
    observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
      self?.restartIfNeeded()
    })
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "isEnabled":
      result(isEnabled)
    case "setEnabled":
      let enabled = args?["enabled"] as? Bool ?? false
      UserDefaults.standard.set(enabled, forKey: enabledKey)
      syncKeepAlive()
      result(nil)
    case "setConnected":
      result(nil)
    case "showMessage", "editMessage":
      post(message: Self.strings(args?["data"]))
      result(nil)
    case "removeMessage":
      let data = Self.strings(args?["data"])
      if let id = Self.identifier(data) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
      }
      result(nil)
    case "showCall":
      post(call: Self.strings(args?["data"]))
      result(nil)
    case "hasNotificationPermission":
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        DispatchQueue.main.async {
          result(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
        }
      }
    case "requestNotificationPermission":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
        DispatchQueue.main.async { result(granted) }
      }
    case "isIgnoringBatteryOptimizations":
      result(true)
    case "requestIgnoreBatteryOptimizations":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func syncKeepAlive() {
    if isEnabled && UIApplication.shared.applicationState == .background {
      startKeepAlive()
    } else if !isEnabled {
      stopKeepAlive()
    }
  }

  private func restartIfNeeded() {
    guard isEnabled, UIApplication.shared.applicationState == .background else { return }
    stopKeepAlive()
    startKeepAlive()
  }

  private func startKeepAlive() {
    guard engine == nil else { return }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try session.setActive(true, options: [])
      let engine = AVAudioEngine()
      let player = AVAudioPlayerNode()
      let format = engine.mainMixerNode.outputFormat(forBus: 0)
      guard format.sampleRate > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate)) else { return }
      buffer.frameLength = buffer.frameCapacity
      engine.attach(player)
      engine.connect(player, to: engine.mainMixerNode, format: format)
      try engine.start()
      player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
      player.play()
      self.engine = engine
      self.player = player
    } catch {
      NSLog("ProMaxLiveConnection: keep-alive failed: \(error)")
      stopKeepAlive()
    }
  }

  private func stopKeepAlive() {
    player?.stop()
    engine?.stop()
    player = nil
    engine = nil
  }

  private func post(message data: [String: String]) {
    guard UIApplication.shared.applicationState != .active,
          let id = Self.identifier(data), let chat = data["mc"] else { return }
    let content = UNMutableNotificationContent()
    let title = data["title"] ?? "ProMax"
    let sender = data["userName"] ?? ""
    let text = data["msg"] ?? "Новое сообщение"
    content.title = title
    content.body = !sender.isEmpty && sender != title ? "\(sender): \(text)" : text
    content.sound = .default
    content.threadIdentifier = "chat-\(chat)"
    content.userInfo = ["chatId": chat, "msgid": data["msgid"] ?? ""]
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
  }

  private func post(call data: [String: String]) {
    guard UIApplication.shared.applicationState != .active else { return }
    let content = UNMutableNotificationContent()
    let video = data["iv"] == "true"
    content.title = data["title"] ?? "ProMax"
    content.body = video ? "Входящий видеозвонок" : "Входящий звонок"
    content.sound = .default
    if let caller = data["callerId"] { content.userInfo = ["chatId": caller] }
    let id = "call-\(data["conversationId"] ?? UUID().uuidString)"
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
  }

  private static func identifier(_ data: [String: String]) -> String? {
    guard let chat = data["mc"], let message = data["msgid"] else { return nil }
    return "msg-\(chat)-\(message)"
  }

  private static func strings(_ raw: Any?) -> [String: String] {
    guard let map = raw as? [AnyHashable: Any] else { return [:] }
    var result: [String: String] = [:]
    for (key, value) in map {
      guard let key = key as? String else { continue }
      if let text = value as? String { result[key] = text } else { result[key] = "\(value)" }
    }
    return result
  }
}
