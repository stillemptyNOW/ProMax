import AVFoundation
import CallKit
import Flutter
import UIKit
#if canImport(WebRTC)
import WebRTC
#endif

final class ProMaxCallKit: NSObject {
  static let shared = ProMaxCallKit()

  private struct Call {
    let conversationId: String
    let video: Bool
    var data: [String: String]
    var answered = false
    var held = false
    var endedByApp = false
  }

  private let ringTimeout: TimeInterval = 60
  private let audioFallbackDelay: TimeInterval = 3
  private let audioReleaseDelay: TimeInterval = 5
  private let controller = CXCallController()
  private var provider: CXProvider?
  private var calls: [UUID: Call] = [:]
  private var ringTimers: [UUID: Timer] = [:]
  private var audioReleaseTimer: Timer?
  private var sink: FlutterEventSink?
  private var backlog: [[String: Any]] = []
  private var appCallActive = false
  private var audioActive = false
  private var manualAudio = false

  func attach(_ sink: FlutterEventSink?) {
    self.sink = sink
    guard let sink = sink else { return }
    let queued = backlog
    backlog.removeAll()
    queued.forEach { sink($0) }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "reportIncoming":
      reportIncoming(args, result: result)
    case "updateCall":
      if let conversationId = args["conversationId"] as? String, let name = args["name"] as? String {
        updateCall(conversationId: conversationId, name: name)
      }
      result(nil)
    case "endCall":
      if let conversationId = args["conversationId"] as? String {
        endCall(conversationId: conversationId, reason: args["reason"] as? String ?? "")
      }
      result(nil)
    case "setMuted":
      if let conversationId = args["conversationId"] as? String {
        setMuted(conversationId: conversationId, muted: args["muted"] as? Bool ?? false)
      }
      result(nil)
    case "setAppCallActive":
      appCallActive = args["active"] as? Bool ?? false
      refreshCallState()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func reportIncoming(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let rawUuid = args["uuid"] as? String,
          let uuid = UUID(uuidString: rawUuid),
          let conversationId = args["conversationId"] as? String else {
      result(false)
      return
    }
    guard calls[uuid] == nil else {
      result(true)
      return
    }
    let video = args["video"] as? Bool ?? false
    let name = args["name"] as? String ?? ""
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: args["handle"] as? String ?? conversationId)
    update.localizedCallerName = name.isEmpty ? nil : name
    update.hasVideo = video
    update.supportsHolding = true
    update.supportsGrouping = false
    update.supportsUngrouping = false
    update.supportsDTMF = false
    calls[uuid] = Call(conversationId: conversationId, video: video, data: Self.strings(args["data"]))
    activeProvider().reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if let error = error, (error as? CXErrorCodeIncomingCallError)?.code != .callUUIDAlreadyExists {
          NSLog("ProMaxCallKit: incoming call was not reported: \(error)")
          self.calls.removeValue(forKey: uuid)
          self.refreshCallState()
          result(false)
          return
        }
        self.startRingTimer(uuid)
        result(true)
      }
    }
  }

  private func activeProvider() -> CXProvider {
    if let provider = provider { return provider }
    let configuration: CXProviderConfiguration
    if #available(iOS 14.0, *) {
      configuration = CXProviderConfiguration()
    } else {
      configuration = CXProviderConfiguration(localizedName: "ProMax")
    }
    configuration.supportsVideo = true
    configuration.maximumCallGroups = 1
    configuration.maximumCallsPerCallGroup = 1
    configuration.supportedHandleTypes = [.generic]
    configuration.includesCallsInRecents = false
    let provider = CXProvider(configuration: configuration)
    provider.setDelegate(self, queue: nil)
    self.provider = provider
    return provider
  }

  private func updateCall(conversationId: String, name: String) {
    guard !name.isEmpty, let uuid = uuid(for: conversationId), let provider = provider else { return }
    calls[uuid]?.data["userName"] = name
    calls[uuid]?.data["title"] = name
    let update = CXCallUpdate()
    update.localizedCallerName = name
    provider.reportCall(with: uuid, updated: update)
  }

  private func endCall(conversationId: String, reason: String) {
    guard let uuid = uuid(for: conversationId) else { return }
    guard reason == "local" else {
      reportEnded(uuid, reason: Self.endedReason(reason))
      return
    }
    calls[uuid]?.endedByApp = true
    controller.request(CXTransaction(action: CXEndCallAction(call: uuid))) { [weak self] error in
      guard let error = error else { return }
      DispatchQueue.main.async {
        NSLog("ProMaxCallKit: end transaction failed: \(error)")
        self?.reportEnded(uuid, reason: .remoteEnded)
      }
    }
  }

  private func reportEnded(_ uuid: UUID, reason: CXCallEndedReason) {
    guard calls[uuid] != nil else { return }
    provider?.reportCall(with: uuid, endedAt: nil, reason: reason)
    finish(uuid)
  }

  private func setMuted(conversationId: String, muted: Bool) {
    guard let uuid = uuid(for: conversationId), calls[uuid]?.answered == true else { return }
    controller.request(CXTransaction(action: CXSetMutedCallAction(call: uuid, muted: muted))) { error in
      guard let error = error else { return }
      NSLog("ProMaxCallKit: mute transaction failed: \(error)")
    }
  }

  private func uuid(for conversationId: String) -> UUID? {
    calls.first { $0.value.conversationId == conversationId }?.key
  }

  private func startRingTimer(_ uuid: UUID) {
    guard let call = calls[uuid], !call.answered, ringTimers[uuid] == nil else { return }
    ringTimers[uuid] = Timer.scheduledTimer(withTimeInterval: ringTimeout, repeats: false) { [weak self] _ in
      self?.ringTimedOut(uuid)
    }
  }

  private func ringTimedOut(_ uuid: UUID) {
    ringTimers.removeValue(forKey: uuid)
    guard let call = calls[uuid], !call.answered else { return }
    reportEnded(uuid, reason: .unanswered)
    emit(["action": "timeout", "conversationId": call.conversationId])
  }

  private func finish(_ uuid: UUID) {
    ringTimers.removeValue(forKey: uuid)?.invalidate()
    calls.removeValue(forKey: uuid)
    if calls.isEmpty && audioActive { scheduleAudioRelease() }
    refreshCallState()
  }

  private func refreshCallState() {
    let inCall = appCallActive || audioActive || calls.values.contains { $0.answered }
    ProMaxLiveConnection.shared.setCallActive(inCall)
    if !inCall { releaseManualAudio() }
  }

  private func prepareCallAudio(video: Bool) {
    manualAudio = true
    #if canImport(WebRTC)
    let rtc = RTCAudioSession.sharedInstance()
    rtc.useManualAudio = true
    rtc.isAudioEnabled = audioActive
    #endif
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playAndRecord,
        mode: video ? .videoChat : .voiceChat,
        options: [.allowBluetooth])
    } catch {
      NSLog("ProMaxCallKit: audio session setup failed: \(error)")
    }
  }

  private func scheduleAudioFallback(_ uuid: UUID) {
    DispatchQueue.main.asyncAfter(deadline: .now() + audioFallbackDelay) { [weak self] in
      guard let self = self, self.manualAudio, let call = self.calls[uuid], call.answered, !call.held,
            !self.audioActive else { return }
      NSLog("ProMaxCallKit: CallKit did not activate audio, WebRTC takes the session itself")
      #if canImport(WebRTC)
      RTCAudioSession.sharedInstance().isAudioEnabled = true
      #endif
    }
  }

  private func scheduleAudioRelease() {
    audioReleaseTimer?.invalidate()
    audioReleaseTimer = Timer.scheduledTimer(withTimeInterval: audioReleaseDelay, repeats: false) { [weak self] _ in
      guard let self = self else { return }
      self.audioReleaseTimer = nil
      guard self.calls.isEmpty, self.audioActive else { return }
      NSLog("ProMaxCallKit: CallKit kept the audio session after the last call, releasing it")
      self.audioActive = false
      self.refreshCallState()
    }
  }

  private func releaseManualAudio() {
    guard manualAudio else { return }
    manualAudio = false
    #if canImport(WebRTC)
    let rtc = RTCAudioSession.sharedInstance()
    rtc.isAudioEnabled = false
    rtc.useManualAudio = false
    #endif
  }

  private func emit(_ event: [String: Any]) {
    if let sink = sink {
      sink(event)
    } else {
      backlog.append(event)
    }
  }

  private static func endedReason(_ name: String) -> CXCallEndedReason {
    switch name {
    case "remoteEnded": return .remoteEnded
    case "unanswered": return .unanswered
    case "declinedElsewhere": return .declinedElsewhere
    case "answeredElsewhere": return .answeredElsewhere
    default: return .failed
    }
  }

  private static func strings(_ raw: Any?) -> [String: String] {
    guard let map = raw as? [AnyHashable: Any] else { return [:] }
    var result: [String: String] = [:]
    for (key, value) in map {
      guard let key = key as? String else { continue }
      result[key] = value as? String ?? "\(value)"
    }
    return result
  }
}

extension ProMaxCallKit: CXProviderDelegate {
  func providerDidReset(_ provider: CXProvider) {
    let dropped = calls.values
    ringTimers.values.forEach { $0.invalidate() }
    ringTimers.removeAll()
    calls.removeAll()
    audioReleaseTimer?.invalidate()
    audioReleaseTimer = nil
    audioActive = false
    refreshCallState()
    for call in dropped {
      emit(["action": "reset", "conversationId": call.conversationId])
    }
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    action.fail()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard let call = calls[action.callUUID] else {
      action.fail()
      return
    }
    ringTimers.removeValue(forKey: action.callUUID)?.invalidate()
    calls[action.callUUID]?.answered = true
    refreshCallState()
    prepareCallAudio(video: call.video)
    scheduleAudioFallback(action.callUUID)
    emit(["action": "answer", "conversationId": call.conversationId, "data": call.data])
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard let call = calls[action.callUUID] else {
      action.fulfill()
      return
    }
    finish(action.callUUID)
    if !call.endedByApp {
      if call.answered {
        emit(["action": "hangup", "conversationId": call.conversationId])
      } else {
        emit(["action": "decline", "conversationId": call.conversationId, "data": call.data])
      }
    }
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    guard let call = calls[action.callUUID] else {
      action.fail()
      return
    }
    emit(["action": "mute", "conversationId": call.conversationId, "muted": action.isMuted])
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
    guard let call = calls[action.callUUID] else {
      action.fail()
      return
    }
    calls[action.callUUID]?.held = action.isOnHold
    emit(["action": "hold", "conversationId": call.conversationId, "onHold": action.isOnHold])
    action.fulfill()
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    audioReleaseTimer?.invalidate()
    audioReleaseTimer = nil
    audioActive = true
    refreshCallState()
    #if canImport(WebRTC)
    let rtc = RTCAudioSession.sharedInstance()
    rtc.audioSessionDidActivate(audioSession)
    if manualAudio { rtc.isAudioEnabled = true }
    #endif
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    audioReleaseTimer?.invalidate()
    audioReleaseTimer = nil
    #if canImport(WebRTC)
    let rtc = RTCAudioSession.sharedInstance()
    rtc.audioSessionDidDeactivate(audioSession)
    if manualAudio { rtc.isAudioEnabled = false }
    #endif
    audioActive = false
    refreshCallState()
  }
}
