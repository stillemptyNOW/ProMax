import AVFoundation
import AVKit
import CoreMedia
import CoreVideo
import Flutter
import UIKit
#if canImport(WebRTC)
import WebRTC
#endif

final class ProMaxCallPip: NSObject {
  static let shared = ProMaxCallPip()

  weak var parentView: UIView?

  private var eligible = false
  private var trackId: String?
  private var host: AnyObject?

  #if canImport(WebRTC)
  private var track: RTCVideoTrack?
  private lazy var sink = ProMaxPipFrameSink { [weak self] sample, size, rotation in
    self?.present(sample, size: size, rotation: rotation)
  }
  #endif

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "update":
      let args = call.arguments as? [String: Any] ?? [:]
      eligible = args["eligible"] as? Bool ?? false
      trackId = args["trackId"] as? String
      apply()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func apply() {
    guard #available(iOS 15.0, *) else { return }
    guard eligible, AVPictureInPictureController.isPictureInPictureSupported(),
          let parent = parentView else {
      teardown()
      return
    }
    if host == nil { host = ProMaxPipHost(parent: parent) }
    attachTrack()
  }

  private func attachTrack() {
    #if canImport(WebRTC)
    let next = trackId.flatMap(Self.videoTrack)
    if next === track { return }
    track?.remove(sink)
    track = next
    next?.add(sink)
    #endif
  }

  private func teardown() {
    #if canImport(WebRTC)
    track?.remove(sink)
    track = nil
    #endif
    if #available(iOS 15.0, *), let current = host as? ProMaxPipHost {
      current.close()
    }
    host = nil
  }

  private func present(_ sample: CMSampleBuffer, size: CGSize, rotation: Int) {
    guard #available(iOS 15.0, *), let current = host as? ProMaxPipHost else { return }
    current.show(sample, size: size, rotation: rotation)
  }

  #if canImport(WebRTC)
  private static func videoTrack(_ id: String) -> RTCVideoTrack? {
    guard let plugin = NSClassFromString("FlutterWebRTCPlugin") as? NSObject.Type else { return nil }
    let singleton = NSSelectorFromString("sharedSingleton")
    guard plugin.responds(to: singleton),
          let instance = plugin.perform(singleton)?.takeUnretainedValue() as? NSObject else {
      return nil
    }
    let lookup = NSSelectorFromString("trackForId:peerConnectionId:")
    guard instance.responds(to: lookup) else { return nil }
    return instance.perform(lookup, with: id, with: nil)?.takeUnretainedValue() as? RTCVideoTrack
  }
  #endif
}

@available(iOS 15.0, *)
private final class ProMaxPipHost: NSObject, AVPictureInPictureControllerDelegate {
  private let sourceView: UIView
  private let videoView: ProMaxPipVideoView
  private let callController: AVPictureInPictureVideoCallViewController
  private let controller: AVPictureInPictureController
  private var contentSize = CGSize.zero

  init(parent: UIView) {
    let source = UIView(frame: parent.bounds)
    source.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    source.isUserInteractionEnabled = false
    source.backgroundColor = .clear
    parent.insertSubview(source, at: 0)
    let call = AVPictureInPictureVideoCallViewController()
    call.view.backgroundColor = .black
    call.preferredContentSize = CGSize(width: 720, height: 1280)
    let video = ProMaxPipVideoView(frame: call.view.bounds)
    video.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    call.view.addSubview(video)
    sourceView = source
    videoView = video
    callController = call
    controller = AVPictureInPictureController(
      contentSource: AVPictureInPictureController.ContentSource(
        activeVideoCallSourceView: source,
        contentViewController: call
      )
    )
    super.init()
    controller.canStartPictureInPictureAutomaticallyFromInline = true
    controller.delegate = self
  }

  func show(_ sample: CMSampleBuffer, size: CGSize, rotation: Int) {
    videoView.setRotation(rotation)
    if size.width > 0, size.height > 0, size != contentSize {
      contentSize = size
      callController.preferredContentSize = size
    }
    videoView.enqueue(sample)
  }

  func close() {
    controller.canStartPictureInPictureAutomaticallyFromInline = false
    if controller.isPictureInPictureActive { controller.stopPictureInPicture() }
    videoView.clear()
    sourceView.removeFromSuperview()
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    completionHandler(true)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    NSLog("ProMaxCallPip: start failed: \(error.localizedDescription)")
  }
}

private final class ProMaxSampleBufferView: UIView {
  override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

  var displayLayer: AVSampleBufferDisplayLayer {
    layer as! AVSampleBufferDisplayLayer
  }
}

private final class ProMaxPipVideoView: UIView {
  private let content = ProMaxSampleBufferView()
  private var rotation = 0

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .black
    clipsToBounds = true
    content.displayLayer.videoGravity = .resizeAspectFill
    addSubview(content)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setRotation(_ degrees: Int) {
    if degrees == rotation { return }
    rotation = degrees
    setNeedsLayout()
  }

  func enqueue(_ sample: CMSampleBuffer) {
    let layer = content.displayLayer
    if layer.status == .failed { layer.flush() }
    layer.enqueue(sample)
  }

  func clear() {
    content.displayLayer.flushAndRemoveImage()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let sideways = rotation % 180 != 0
    content.transform = .identity
    content.bounds = CGRect(
      x: 0,
      y: 0,
      width: sideways ? bounds.height : bounds.width,
      height: sideways ? bounds.width : bounds.height
    )
    content.center = CGPoint(x: bounds.midX, y: bounds.midY)
    content.transform = CGAffineTransform(rotationAngle: CGFloat(rotation) * .pi / 180)
  }
}

#if canImport(WebRTC)
private final class ProMaxPipFrameSink: NSObject, RTCVideoRenderer {
  private let onSample: (CMSampleBuffer, CGSize, Int) -> Void
  private var pool: CVPixelBufferPool?
  private var poolWidth = 0
  private var poolHeight = 0

  init(onSample: @escaping (CMSampleBuffer, CGSize, Int) -> Void) {
    self.onSample = onSample
  }

  func setSize(_ size: CGSize) {}

  func renderFrame(_ frame: RTCVideoFrame?) {
    guard let frame = frame, let pixelBuffer = pixelBuffer(of: frame),
          let sample = Self.sampleBuffer(pixelBuffer) else { return }
    let rotation = frame.rotation.rawValue
    let width = CGFloat(frame.width)
    let height = CGFloat(frame.height)
    let size = rotation % 180 != 0
      ? CGSize(width: height, height: width)
      : CGSize(width: width, height: height)
    let deliver = onSample
    DispatchQueue.main.async {
      deliver(sample, size, rotation)
    }
  }

  private func pixelBuffer(of frame: RTCVideoFrame) -> CVPixelBuffer? {
    if let native = frame.buffer as? RTCCVPixelBuffer {
      return native.pixelBuffer
    }
    let i420 = frame.buffer.toI420()
    let width = Int(i420.width)
    let height = Int(i420.height)
    guard width > 0, height > 0, let target = makeBuffer(width: width, height: height) else {
      return nil
    }
    CVPixelBufferLockBaseAddress(target, [])
    defer { CVPixelBufferUnlockBaseAddress(target, []) }
    guard let lumaBase = CVPixelBufferGetBaseAddressOfPlane(target, 0),
          let chromaBase = CVPixelBufferGetBaseAddressOfPlane(target, 1) else { return nil }
    let luma = lumaBase.assumingMemoryBound(to: UInt8.self)
    let chroma = chromaBase.assumingMemoryBound(to: UInt8.self)
    let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(target, 0)
    let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(target, 1)
    let srcY: UnsafePointer<UInt8> = i420.dataY
    let srcU: UnsafePointer<UInt8> = i420.dataU
    let srcV: UnsafePointer<UInt8> = i420.dataV
    let strideY = Int(i420.strideY)
    let strideU = Int(i420.strideU)
    let strideV = Int(i420.strideV)
    for row in 0..<height {
      memcpy(luma + row * lumaStride, srcY + row * strideY, width)
    }
    let chromaWidth = (width + 1) / 2
    let chromaHeight = (height + 1) / 2
    for row in 0..<chromaHeight {
      let dst = chroma + row * chromaStride
      let u = srcU + row * strideU
      let v = srcV + row * strideV
      for col in 0..<chromaWidth {
        dst[col * 2] = u[col]
        dst[col * 2 + 1] = v[col]
      }
    }
    return target
  }

  private func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
    if pool == nil || poolWidth != width || poolHeight != height {
      let attributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String:
          kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
      ]
      var created: CVPixelBufferPool?
      CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &created)
      pool = created
      poolWidth = width
      poolHeight = height
    }
    guard let pool = pool else { return nil }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
    return buffer
  }

  private static func sampleBuffer(_ pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
    var format: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescriptionOut: &format
    )
    guard let description = format else { return nil }
    var timing = CMSampleTimingInfo(
      duration: .invalid,
      presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
      decodeTimeStamp: .invalid
    )
    var sample: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescription: description,
      sampleTiming: &timing,
      sampleBufferOut: &sample
    )
    guard let ready = sample else { return nil }
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(ready, createIfNecessary: true),
       CFArrayGetCount(attachments) > 0 {
      let dictionary = unsafeBitCast(
        CFArrayGetValueAtIndex(attachments, 0),
        to: CFMutableDictionary.self
      )
      CFDictionarySetValue(
        dictionary,
        Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
        Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
      )
    }
    return ready
  }
}
#endif
