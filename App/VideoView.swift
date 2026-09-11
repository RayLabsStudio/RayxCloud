// VideoView.swift
// Video surface backed by AVSampleBufferDisplayLayer. Decoded NV12 frames from
// VideoToolbox are wrapped in CMSampleBuffers and displayed immediately.
//

import SwiftUI
import AVFoundation
import CoreMedia
#if WEBRTC_AVAILABLE
import WebRTC
#endif

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

    static func dismantleUIView(_ uiView: SampleBufferVideoView, coordinator: Coordinator) {
        coordinator.attach(nil, to: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
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
            guard let next else {
                print("[VideoView] detached track")
                return
            }
            let renderer = SampleBufferRenderer(layer: view.displayLayer)
            self.renderer = renderer
            print("[VideoView] attaching track id=\(next.trackId) enabled=\(next.isEnabled) viewBounds=\(view.bounds.size)")
            next.add(renderer)
        }
#else
        func attach(_ track: AnyObject?, to view: SampleBufferVideoView) {}
#endif
    }
}

final class SampleBufferVideoView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var displayLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }

    private var layoutLogCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if layoutLogCount < 3 {
            layoutLogCount += 1
            print("[VideoView] layout bounds=\(bounds.size) window=\(window != nil)")
        }
    }
}

#if WEBRTC_AVAILABLE
/// Feeds WebRTC frames into an AVSampleBufferDisplayLayer. Called on WebRTC's
/// decoder thread; the AVFoundation renderer is safe to enqueue from any thread.
final class SampleBufferRenderer: NSObject, RTCVideoRenderer, @unchecked Sendable {
    private let videoRenderer: AVSampleBufferVideoRenderer
    private var formatDescription: CMVideoFormatDescription?
    private var formatDimensions = CMVideoDimensions(width: 0, height: 0)
    private var frameCount = 0
    private var failureCount = 0

    init(layer: AVSampleBufferDisplayLayer) {
        videoRenderer = layer.sampleBufferRenderer
        super.init()
    }

    func setSize(_ size: CGSize) {
        print("[VideoView] source size \(size)")
    }

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        frameCount += 1

        guard let cvBuffer = frame.buffer as? RTCCVPixelBuffer else {
            if frameCount <= 3 {
                print("[VideoView] unsupported frame buffer \(type(of: frame.buffer))")
            }
            return
        }
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

        if frameCount <= 3 || frameCount % 600 == 0 {
            print("[VideoView] enqueued frame #\(frameCount) \(frame.width)x\(frame.height) rendererStatus=\(videoRenderer.status.rawValue)")
        }
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
