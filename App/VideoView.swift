// VideoView.swift
// Video surface backed by AVSampleBufferDisplayLayer on both iOS and macOS.
// Decoded NV12 frames from VideoToolbox are wrapped in CMSampleBuffers and
// displayed immediately.
//

import SwiftUI
import AVFoundation
import CoreMedia
#if WEBRTC_AVAILABLE
import WebRTC
#endif

#if os(iOS)
struct VideoView: UIViewRepresentable {
    let videoTrack: AnyObject?

    func makeUIView(context: Context) -> SampleBufferVideoView {
        let view = SampleBufferVideoView()
        context.coordinator.attach(videoTrack, to: view)
        return view
    }

    func updateUIView(_ uiView: SampleBufferVideoView, context: Context) {
        context.coordinator.attach(videoTrack, to: uiView)
    }

    static func dismantleUIView(_ uiView: SampleBufferVideoView, coordinator: VideoViewCoordinator) {
        coordinator.attach(nil, to: uiView)
    }

    func makeCoordinator() -> VideoViewCoordinator {
        VideoViewCoordinator()
    }
}

final class SampleBufferVideoView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var displayLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
#else
struct VideoView: NSViewRepresentable {
    let videoTrack: AnyObject?

    func makeNSView(context: Context) -> SampleBufferVideoView {
        let view = SampleBufferVideoView()
        context.coordinator.attach(videoTrack, to: view)
        return view
    }

    func updateNSView(_ nsView: SampleBufferVideoView, context: Context) {
        context.coordinator.attach(videoTrack, to: nsView)
    }

    static func dismantleNSView(_ nsView: SampleBufferVideoView, coordinator: VideoViewCoordinator) {
        coordinator.attach(nil, to: nsView)
    }

    func makeCoordinator() -> VideoViewCoordinator {
        VideoViewCoordinator()
    }
}

final class SampleBufferVideoView: NSView {
    var displayLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func makeBackingLayer() -> CALayer {
        let displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        return displayLayer
    }
}
#endif

@MainActor
final class VideoViewCoordinator {
#if WEBRTC_AVAILABLE
    private var attachedTrack: RTCVideoTrack?
    private var renderer: SampleBufferRenderer?

    func attach(_ track: AnyObject?, to view: SampleBufferVideoView) {
        let next = track as? RTCVideoTrack
        guard next !== attachedTrack else { return }
        if let attachedTrack, let renderer {
            attachedTrack.remove(renderer)
        }
        attachedTrack = next
        renderer = nil
        guard let next else { return }
        let renderer = SampleBufferRenderer(layer: view.displayLayer)
        self.renderer = renderer
        next.add(renderer)
    }
#else
    func attach(_ track: AnyObject?, to view: SampleBufferVideoView) {}
#endif
}

#if WEBRTC_AVAILABLE
/// Feeds WebRTC frames into an AVSampleBufferDisplayLayer. Called on WebRTC's
/// decoder thread; the AVFoundation renderer is safe to enqueue from any thread.
final class SampleBufferRenderer: NSObject, RTCVideoRenderer, @unchecked Sendable {
    private let videoRenderer: AVSampleBufferVideoRenderer
    private var formatDescription: CMVideoFormatDescription?
    private var formatDimensions = CMVideoDimensions(width: 0, height: 0)
    private var failureCount = 0

    init(layer: AVSampleBufferDisplayLayer) {
        videoRenderer = layer.sampleBufferRenderer
        super.init()
    }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame, let cvBuffer = frame.buffer as? RTCCVPixelBuffer else { return }
        let pixelBuffer = cvBuffer.pixelBuffer
        guard let format = formatDescription(for: pixelBuffer) else { return }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: frame.timeStampNs, timescale: 1_000_000_000),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            if failureCount < 3 {
                failureCount += 1
                print("[VideoView] sample buffer create failed status=\(status)")
            }
            return
        }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) as? [CFMutableDictionary],
           let first = attachments.first {
            CFDictionarySetValue(
                first,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        if videoRenderer.status == .failed {
            print("[VideoView] renderer failed: \(String(describing: videoRenderer.error)), flushing")
            videoRenderer.flush()
        }
        videoRenderer.enqueue(sampleBuffer)
    }

    private func formatDescription(for pixelBuffer: CVPixelBuffer) -> CMVideoFormatDescription? {
        let width = Int32(CVPixelBufferGetWidth(pixelBuffer))
        let height = Int32(CVPixelBufferGetHeight(pixelBuffer))
        if let formatDescription,
           formatDimensions.width == width, formatDimensions.height == height {
            return formatDescription
        }
        var description: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &description
        )
        guard status == noErr, let description else {
            print("[VideoView] format description failed status=\(status)")
            return nil
        }
        formatDescription = description
        formatDimensions = CMVideoDimensions(width: width, height: height)
        return description
    }
}
#endif
