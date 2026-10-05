import AVFoundation
import CoreImage
import Flutter
import PhotosUI
import UniformTypeIdentifiers
import UIKit

private struct VideoExportSpec {
  let input: String
  let output: String
  let startMs: Int?
  let endMs: Int?
  let removeAudio: Bool
  let rotationDegrees: Double
  let flipH: Bool
  let crop: [Double]?
  let outWidth: Int
  let outHeight: Int
  let rgbMatrix: [Double]?
  let overlay: String?
  let centerSquare: Bool

  init?(_ arguments: Any?) {
    guard let args = arguments as? [String: Any],
          let input = args["input"] as? String,
          let output = args["output"] as? String else { return nil }
    self.input = input
    self.output = output
    startMs = (args["startMs"] as? NSNumber)?.intValue
    endMs = (args["endMs"] as? NSNumber)?.intValue
    removeAudio = (args["removeAudio"] as? NSNumber)?.boolValue ?? false
    rotationDegrees = (args["rotationDegrees"] as? NSNumber)?.doubleValue ?? 0
    flipH = (args["flipH"] as? NSNumber)?.boolValue ?? false
    crop = (args["crop"] as? [NSNumber])?.map { $0.doubleValue }
    outWidth = (args["outWidth"] as? NSNumber)?.intValue ?? 0
    outHeight = (args["outHeight"] as? NSNumber)?.intValue ?? 0
    rgbMatrix = (args["rgbMatrix"] as? [NSNumber])?.map { $0.doubleValue }
    overlay = args["overlay"] as? String
    centerSquare = false
  }

  init(input: String, output: String, edge: Int, maxDurationMs: Int? = nil) {
    self.input = input
    self.output = output
    startMs = nil
    endMs = maxDurationMs
    removeAudio = false
    rotationDegrees = 0
    flipH = false
    crop = nil
    outWidth = edge
    outHeight = edge
    rgbMatrix = nil
    overlay = nil
    centerSquare = true
  }
}

final class ProMaxVideo: NSObject, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
  static let shared = ProMaxVideo()

  private let queue = DispatchQueue(label: "io.github.stillemptynow.promax.video", qos: .userInitiated)
  private var session: AVAssetExportSession?
  private var cancelled = false
  private var pickerResult: FlutterResult?
  private var documentResult: FlutterResult?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "exportPromaxArchive":
      exportPromaxArchive(call.arguments, result)
    case "pickGalleryVideo":
      pickGalleryVideo(result)
    case "probe":
      probe(call.arguments, result)
    case "frames":
      frames(call.arguments, result)
    case "cropSquare":
      cropSquare(call.arguments, result)
    case "edit":
      guard let spec = VideoExportSpec(call.arguments) else {
        result(FlutterError(code: "BAD_ARGS", message: "input/output required", details: nil))
        return
      }
      export(spec) { ok in result(NSNumber(value: ok)) }
    case "editProgress":
      let value = session.map { Int(($0.progress * 100).rounded()) } ?? -1
      result(NSNumber(value: value))
    case "editCancel":
      cancelled = true
      session?.cancelExport()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func pickGalleryVideo(_ result: @escaping FlutterResult) {
    guard pickerResult == nil else {
      result(FlutterError(code: "PICKER_BUSY", message: "Выбор видео уже открыт", details: nil))
      return
    }
    guard var presenter = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows })
      .first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "NO_WINDOW", message: "Не удалось открыть галерею", details: nil))
      return
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    var configuration = PHPickerConfiguration()
    configuration.filter = .videos
    configuration.selectionLimit = 1
    configuration.preferredAssetRepresentationMode = .current
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = self
    pickerResult = result
    presenter.present(picker, animated: true)
  }

  private func exportPromaxArchive(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard documentResult == nil,
          let args = arguments as? [String: Any], let path = args["path"] as? String,
          path.hasSuffix(".promax"), FileManager.default.fileExists(atPath: path),
          var presenter = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "EXPORT_UNAVAILABLE", message: "Не удалось открыть сохранение файла", details: nil))
      return
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    let picker = UIDocumentPickerViewController(forExporting: [URL(fileURLWithPath: path)], asCopy: true)
    picker.delegate = self
    documentResult = result
    presenter.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    documentResult?(urls.first?.absoluteString)
    documentResult = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    documentResult?(nil)
    documentResult = nil
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    guard let callback = pickerResult else { return }
    pickerResult = nil
    picker.dismiss(animated: true)
    guard let provider = results.first?.itemProvider else {
      callback(nil)
      return
    }
    provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
      guard let source = url else {
        Self.reply(callback, FlutterError(code: "VIDEO_UNAVAILABLE", message: "Не удалось загрузить видео из галереи", details: nil))
        return
      }
      let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("promax_gallery_\(UUID().uuidString)")
        .appendingPathExtension(source.pathExtension.isEmpty ? "mov" : source.pathExtension)
      do {
        try FileManager.default.copyItem(at: source, to: destination)
        Self.reply(callback, destination.path)
      } catch {
        Self.reply(callback, FlutterError(code: "VIDEO_COPY_FAILED", message: "Не удалось сохранить выбранное видео", details: nil))
      }
    }
  }

  private func probe(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any], let input = args["input"] as? String else {
      result(FlutterError(code: "BAD_ARGS", message: "input required", details: nil))
      return
    }
    queue.async {
      let asset = AVURLAsset(url: URL(fileURLWithPath: input))
      guard let track = asset.tracks(withMediaType: .video).first else {
        Self.reply(result, nil)
        return
      }
      let size = track.naturalSize.applying(track.preferredTransform)
      let seconds = CMTimeGetSeconds(asset.duration)
      guard size.width.isFinite, size.height.isFinite,
            abs(size.width) > 0, abs(size.height) > 0,
            abs(size.width) < 65536, abs(size.height) < 65536,
            seconds.isFinite, seconds > 0, seconds < 86400000 else {
        Self.reply(result, nil)
        return
      }
      let durationMs = Int((seconds * 1000).rounded())
      let fps = Double(track.nominalFrameRate)
      let payload: [String: Any] = [
        "width": Int(abs(size.width).rounded()),
        "height": Int(abs(size.height).rounded()),
        "durationMs": durationMs,
        "fps": fps.isFinite && fps > 0 ? fps : 30.0,
        "hasAudio": !asset.tracks(withMediaType: .audio).isEmpty,
      ]
      Self.reply(result, payload)
    }
  }

  private func frames(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any],
          let input = args["input"] as? String,
          let times = args["times"] as? [NSNumber] else {
      result(FlutterError(code: "BAD_ARGS", message: "input/times required", details: nil))
      return
    }
    let edge = (args["size"] as? NSNumber)?.intValue ?? 256
    let precise = (args["precise"] as? NSNumber)?.boolValue ?? false
    queue.async {
      let asset = AVURLAsset(url: URL(fileURLWithPath: input))
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = CGSize(width: edge, height: edge)
      if precise {
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
      }
      var output: [Any] = []
      for time in times {
        let at = CMTime(value: CMTimeValue(time.int64Value), timescale: 1000)
        guard let cgImage = try? generator.copyCGImage(at: at, actualTime: nil),
              let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.9) else {
          output.append(NSNull())
          continue
        }
        output.append(FlutterStandardTypedData(bytes: data))
      }
      Self.reply(result, output)
    }
  }

  private func cropSquare(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any],
          let input = args["input"] as? String,
          let output = args["output"] as? String else {
      result(FlutterError(code: "BAD_ARGS", message: "input/output required", details: nil))
      return
    }
    let edge = (args["size"] as? NSNumber)?.intValue ?? 480
    let maxDuration = (args["maxDurationMs"] as? NSNumber)?.intValue
    export(VideoExportSpec(input: input, output: output, edge: edge, maxDurationMs: maxDuration)) { ok in
      if ok {
        result(output)
      } else {
        result(FlutterError(code: "TRANSCODE_FAILED", message: "export failed", details: nil))
      }
    }
  }

  private func export(_ spec: VideoExportSpec, completion: @escaping (Bool) -> Void) {
    queue.async {
      self.cancelled = false
      let asset = AVURLAsset(url: URL(fileURLWithPath: spec.input))
      guard let videoTrack = asset.tracks(withMediaType: .video).first else {
        Self.reply { completion(false) }
        return
      }

      let totalSeconds = CMTimeGetSeconds(asset.duration)
      guard totalSeconds.isFinite, totalSeconds > 0, totalSeconds < 86400000,
            (spec.startMs ?? 0) >= 0 else {
        Self.reply { completion(false) }
        return
      }
      let start = CMTime(value: CMTimeValue(spec.startMs ?? 0), timescale: 1000)
      let totalMs = totalSeconds.isFinite ? Int((totalSeconds * 1000).rounded()) : 0
      let endMs = min(spec.endMs ?? totalMs, totalMs)
      let end = CMTime(value: CMTimeValue(max(endMs, spec.startMs ?? 0)), timescale: 1000)
      let range = CMTimeRange(start: start, end: end)
      guard range.duration.seconds > 0 else {
        Self.reply { completion(false) }
        return
      }

      let composition = AVMutableComposition()
      guard let compositionVideo = composition.addMutableTrack(
        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
        Self.reply { completion(false) }
        return
      }
      do {
        try compositionVideo.insertTimeRange(range, of: videoTrack, at: .zero)
      } catch {
        Self.reply { completion(false) }
        return
      }
      compositionVideo.preferredTransform = videoTrack.preferredTransform

      if !spec.removeAudio,
         let audioTrack = asset.tracks(withMediaType: .audio).first,
         let compositionAudio = composition.addMutableTrack(
          withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
        try? compositionAudio.insertTimeRange(range, of: audioTrack, at: .zero)
      }

      let natural = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
      guard natural.width.isFinite, natural.height.isFinite,
            abs(natural.width) > 0, abs(natural.height) > 0,
            abs(natural.width) < 65536, abs(natural.height) < 65536 else {
        Self.reply { completion(false) }
        return
      }
      let outWidth = spec.outWidth > 0 ? spec.outWidth : Int(abs(natural.width).rounded())
      let outHeight = spec.outHeight > 0 ? spec.outHeight : Int(abs(natural.height).rounded())
      guard outWidth > 0, outHeight > 0, outWidth <= 8192, outHeight <= 8192 else {
        Self.reply { completion(false) }
        return
      }

      let transform = videoTrack.preferredTransform
      let overlay = spec.overlay.flatMap { UIImage(contentsOfFile: $0) }.flatMap { CIImage(image: $0) }
      let renderSize = CGSize(width: outWidth, height: outHeight)

      let videoComposition: AVMutableVideoComposition
      if spec.centerSquare {
        let bounds = CGRect(origin: .zero, size: videoTrack.naturalSize).applying(transform)
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else {
          Self.reply { completion(false) }
          return
        }
        let scale = max(renderSize.width / bounds.width, renderSize.height / bounds.height)
        let cropTransform = transform
          .concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
          .concatenating(CGAffineTransform(scaleX: scale, y: scale))
          .concatenating(CGAffineTransform(
            translationX: (renderSize.width - bounds.width * scale) / 2,
            y: (renderSize.height - bounds.height * scale) / 2))
        compositionVideo.preferredTransform = .identity
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideo)
        layer.setTransform(cropTransform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: range.duration)
        instruction.layerInstructions = [layer]
        videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
      } else {
        videoComposition = AVMutableVideoComposition(asset: composition) { request in
          let image = Self.render(
            request.sourceImage,
            spec: spec,
            transform: transform,
            overlay: overlay,
            renderSize: renderSize)
          request.finish(with: image, context: nil)
        }
      }
      videoComposition.renderSize = renderSize

      let outputURL = URL(fileURLWithPath: spec.output)
      try? FileManager.default.removeItem(at: outputURL)

      guard let session = AVAssetExportSession(
        asset: composition,
        presetName: spec.centerSquare ? AVAssetExportPreset1920x1080 : AVAssetExportPresetHighestQuality) else {
        Self.reply { completion(false) }
        return
      }
      session.outputURL = outputURL
      session.outputFileType = .mp4
      session.videoComposition = videoComposition
      session.shouldOptimizeForNetworkUse = true
      self.session = session

      session.exportAsynchronously {
        let ok = session.status == .completed && !self.cancelled
        self.session = nil
        if !ok { try? FileManager.default.removeItem(at: outputURL) }
        Self.reply { completion(ok) }
      }
    }
  }

  private static func render(
    _ source: CIImage,
    spec: VideoExportSpec,
    transform: CGAffineTransform,
    overlay: CIImage?,
    renderSize: CGSize
  ) -> CIImage {
    var image = normalized(source.transformed(by: transform))

    if spec.flipH {
      image = normalized(image.transformed(by: CGAffineTransform(scaleX: -1, y: 1)))
    }
    if abs(spec.rotationDegrees) > 0.01 {
      let radians = CGFloat(spec.rotationDegrees * .pi / 180)
      image = normalized(image.transformed(by: CGAffineTransform(rotationAngle: radians)))
    }
    if spec.centerSquare {
      let extent = image.extent
      let side = min(extent.width, extent.height)
      image = normalized(image.cropped(to: CGRect(
        x: extent.midX - side / 2,
        y: extent.midY - side / 2,
        width: side,
        height: side)))
    } else if let crop = spec.crop, crop.count == 4 {
      let extent = image.extent
      let left = CGFloat((crop[0] + 1) / 2)
      let right = CGFloat((crop[1] + 1) / 2)
      let bottom = CGFloat((1 - crop[2]) / 2)
      let top = CGFloat((1 - crop[3]) / 2)
      let rect = CGRect(
        x: extent.minX + left * extent.width,
        y: extent.minY + (1 - bottom) * extent.height,
        width: max(1, (right - left) * extent.width),
        height: max(1, (bottom - top) * extent.height))
      image = normalized(image.cropped(to: rect))
    }

    let extent = image.extent
    if extent.width > 0, extent.height > 0 {
      image = image.transformed(by: CGAffineTransform(
        scaleX: renderSize.width / extent.width,
        y: renderSize.height / extent.height))
      image = normalized(image)
    }

    if let matrix = spec.rgbMatrix, matrix.count == 16,
       let filter = CIFilter(name: "CIColorMatrix") {
      filter.setValue(image, forKey: kCIInputImageKey)
      filter.setValue(vector(matrix, 0, 4, 8), forKey: "inputRVector")
      filter.setValue(vector(matrix, 1, 5, 9), forKey: "inputGVector")
      filter.setValue(vector(matrix, 2, 6, 10), forKey: "inputBVector")
      filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
      filter.setValue(vector(matrix, 12, 13, 14), forKey: "inputBiasVector")
      if let output = filter.outputImage { image = output }
    }

    if let overlay = overlay {
      image = overlay.composited(over: image)
    }

    return image.cropped(to: CGRect(origin: .zero, size: renderSize))
  }

  private static func vector(_ m: [Double], _ x: Int, _ y: Int, _ z: Int) -> CIVector {
    CIVector(x: CGFloat(m[x]), y: CGFloat(m[y]), z: CGFloat(m[z]), w: 0)
  }

  private static func normalized(_ image: CIImage) -> CIImage {
    let extent = image.extent
    guard extent.origin != .zero else { return image }
    return image.transformed(
      by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
  }

  private static func reply(_ result: @escaping FlutterResult, _ value: Any?) {
    DispatchQueue.main.async { result(value) }
  }

  private static func reply(_ block: @escaping () -> Void) {
    DispatchQueue.main.async(execute: block)
  }
}
