import CoreImage
import Flutter
import NaturalLanguage
import SwiftUI
import UIKit
import Vision
#if canImport(Translation)
import Translation
#endif

enum ProMaxTranslation {
  private static let minimumConfidence = 0.5

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "capabilities":
      result([
        "available": isAvailable,
        "manageModels": false,
        "wifiOnlyOption": false,
      ])
    case "detect":
      result(detect(args["text"] as? String ?? ""))
    case "translate":
      translate(args, result)
    case "models":
      result([String]())
    case "deleteModel":
      result(false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static var isAvailable: Bool {
    #if canImport(Translation)
    if #available(iOS 18.0, *) {
      return true
    }
    #endif
    return false
  }

  static func detect(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(trimmed)
    guard let best = recognizer.languageHypotheses(withMaximum: 1).first,
          best.value >= minimumConfidence,
          best.key != .undetermined else {
      return nil
    }
    return best.key.rawValue
  }

  private static func primary(_ tag: String) -> String {
    let lowered = tag.lowercased()
    let separators = CharacterSet(charactersIn: "-_")
    return lowered.components(separatedBy: separators).first ?? lowered
  }

  private static func translate(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let text = args["text"] as? String, !text.isEmpty,
          let target = args["target"] as? String else {
      result(FlutterError(code: "invalid", message: "text and target are required", details: nil))
      return
    }
    guard let source = (args["source"] as? String) ?? detect(text) else {
      result(FlutterError(code: "undetermined", message: "source language is unknown", details: nil))
      return
    }
    if primary(source) == primary(target) {
      result(["text": text, "source": source, "same": true])
      return
    }
    #if canImport(Translation)
    if #available(iOS 18.0, *) {
      ProMaxTranslationHost.shared.enqueue(
        ProMaxTranslationJob(text: text, source: source, target: target, result: result)
      )
      return
    }
    #endif
    result(FlutterError(code: "unsupported", message: "Translation needs iOS 18", details: nil))
  }
}

#if canImport(Translation)
struct ProMaxTranslationJob {
  let text: String
  let source: String
  let target: String
  let result: FlutterResult
}

@available(iOS 18.0, *)
final class ProMaxTranslationHost: ObservableObject {
  static let shared = ProMaxTranslationHost()

  @Published var configuration: TranslationSession.Configuration?

  private var queue: [ProMaxTranslationJob] = []
  private var running = false
  private var controller: UIHostingController<ProMaxTranslationView>?

  func enqueue(_ job: ProMaxTranslationJob) {
    queue.append(job)
    guard attach() else {
      failAll(code: "unavailable")
      return
    }
    pump()
  }

  private func attach() -> Bool {
    if let controller, controller.parent != nil {
      return true
    }
    guard let window = UIApplication.shared.delegate?.window ?? nil,
          let root = window.rootViewController else {
      return false
    }
    let hosting = UIHostingController(rootView: ProMaxTranslationView(host: self))
    hosting.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
    hosting.view.backgroundColor = .clear
    hosting.view.alpha = 0
    hosting.view.isUserInteractionEnabled = false
    root.addChild(hosting)
    root.view.addSubview(hosting.view)
    hosting.didMove(toParent: root)
    controller = hosting
    return true
  }

  private func pump() {
    guard !running, let next = queue.first else { return }
    running = true
    let wanted = TranslationSession.Configuration(
      source: Locale.Language(identifier: next.source),
      target: Locale.Language(identifier: next.target)
    )
    if configuration?.source == wanted.source && configuration?.target == wanted.target {
      configuration?.invalidate()
    } else {
      configuration = wanted
    }
  }

  private func matches(_ job: ProMaxTranslationJob, _ pair: TranslationSession.Configuration) -> Bool {
    Locale.Language(identifier: job.source) == pair.source
      && Locale.Language(identifier: job.target) == pair.target
  }

  @MainActor
  func run(_ session: TranslationSession) async {
    guard let pair = configuration else {
      running = false
      return
    }
    while let job = queue.first, matches(job, pair) {
      queue.removeFirst()
      do {
        let response = try await session.translate(job.text)
        job.result(["text": response.targetText, "source": job.source, "same": false])
      } catch {
        job.result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
      }
    }
    running = false
    pump()
  }

  private func failAll(code: String) {
    let pending = queue
    queue.removeAll()
    running = false
    for job in pending {
      job.result(FlutterError(code: code, message: nil, details: nil))
    }
  }
}

@available(iOS 18.0, *)
struct ProMaxTranslationView: View {
  @ObservedObject var host: ProMaxTranslationHost

  var body: some View {
    Color.clear
      .frame(width: 1, height: 1)
      .translationTask(host.configuration) { session in
        await host.run(session)
      }
  }
}
#endif

enum ProMaxSubjectLift {
  private static let maxSide: CGFloat = 1536
  private static let cacheDirectory = "sticker_lift"

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "available":
      result(isAvailable)
    case "lift":
      guard isAvailable,
            let path = (call.arguments as? [String: Any])?["path"] as? String else {
        result(nil)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let output = lift(path)
        DispatchQueue.main.async { result(output) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static var isAvailable: Bool {
    #if targetEnvironment(simulator)
    return false
    #else
    if #available(iOS 17.0, *) {
      return true
    }
    return false
    #endif
  }

  private static func lift(_ path: String) -> String? {
    guard #available(iOS 17.0, *) else { return nil }
    guard let image = UIImage(contentsOfFile: path), let cgImage = normalized(image) else {
      return nil
    }
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    let request = VNGenerateForegroundInstanceMaskRequest()
    do {
      try handler.perform([request])
      guard let observation = request.results?.first else { return nil }
      let buffer = try observation.generateMaskedImage(
        ofInstances: observation.allInstances,
        from: handler,
        croppedToInstancesExtent: true
      )
      let masked = CIImage(cvPixelBuffer: buffer)
      guard let output = CIContext().createCGImage(masked, from: masked.extent),
            let data = UIImage(cgImage: output).pngData() else {
        return nil
      }
      return store(data)
    } catch {
      return nil
    }
  }

  private static func normalized(_ image: UIImage) -> CGImage? {
    let size = image.size
    let longest = max(size.width, size.height)
    guard longest > 0 else { return nil }
    let scale = min(1, maxSide / longest)
    let target = CGSize(
      width: max(1, (size.width * scale).rounded()),
      height: max(1, (size.height * scale).rounded())
    )
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
    return rendered.cgImage
  }

  private static func store(_ data: Data) -> String? {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(cacheDirectory, isDirectory: true)
    let manager = FileManager.default
    try? manager.removeItem(at: directory)
    do {
      try manager.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appendingPathComponent("lift_\(Int(Date().timeIntervalSince1970 * 1000)).png")
      try data.write(to: url)
      return url.path
    } catch {
      return nil
    }
  }
}
