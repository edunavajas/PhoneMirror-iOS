import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

final class VideoEncoder {
    private var session: VTCompressionSession?
    private let codec: VideoCodec
    private let bitrate: Int
    private var formatSent = false
    private let lock = NSLock()
    private var forceKeyframeNext = false

    var onFormat: ((VideoFormatMessage) -> Void)?
    var onFrame: ((VideoFrameMessage) -> Void)?
    var onError: ((String) -> Void)?

    init(width: Int32, height: Int32, fps: Int32, codec: VideoCodec = .h264, bitrate: Int = 8_000_000) {
        self.codec = codec
        self.bitrate = bitrate
        var spec: [String: Any] = [:]
        if #available(iOS 17.4, macOS 14.0, *) {
            spec[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String] = true
        }
        var s: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width, height: height,
            codecType: codec == .hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264,
            encoderSpecification: spec.isEmpty ? nil : (spec as CFDictionary),
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: { refcon, _, status, _, sampleBuffer in
                guard status == noErr, let refcon, let sampleBuffer,
                      CMSampleBufferDataIsReady(sampleBuffer) else { return }
                Unmanaged<VideoEncoder>.fromOpaque(refcon).takeUnretainedValue().handle(sampleBuffer)
            },
            refcon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            compressionSessionOut: &s)
        guard status == noErr, let session = s else {
            onError?("VTCompressionSessionCreate failed: \(status)")
            return
        }
        self.session = session
        configure(fps: fps)
    }

    private func configure(fps: Int32) {
        guard let session else { return }
        func set(_ key: CFString, _ value: CFTypeRef?) {
            VTSessionSetProperty(session, key: key, value: value)
        }
        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        set(kVTCompressionPropertyKey_ProfileLevel,
            codec == .hevc ? kVTProfileLevel_HEVC_Main_AutoLevel : kVTProfileLevel_H264_High_AutoLevel)
        set(kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: fps))
        set(kVTCompressionPropertyKey_MaxKeyFrameInterval, NSNumber(value: fps * 2))
        set(kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: bitrate))
        set(kVTCompressionPropertyKey_DataRateLimits,
            [NSNumber(value: bitrate / 8), NSNumber(value: 1.0)] as CFArray)
        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    /// True once a compression session was created successfully.
    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return session != nil
    }

    func encode(_ pixelBuffer: CVPixelBuffer, pts: CMTime) {
        lock.lock()
        guard let session else { lock.unlock(); return }
        let force = forceKeyframeNext
        forceKeyframeNext = false
        let properties: CFDictionary? = force
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary
            : nil
        var flags: VTEncodeInfoFlags = []
        let status = VTCompressionSessionEncodeFrame(
            session, imageBuffer: pixelBuffer,
            presentationTimeStamp: pts, duration: .invalid,
            frameProperties: properties, sourceFrameRefcon: nil, infoFlagsOut: &flags)
        lock.unlock()
        if status != noErr { onError?("encode failed: \(status)") }
    }

    /// Ask the encoder to emit an IDR on the next frame (used when a viewer connects).
    func forceKeyframe() {
        lock.lock()
        forceKeyframeNext = true
        lock.unlock()
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        guard let session else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
        self.session = nil
    }

    deinit { invalidate() }

    private func handle(_ sb: CMSampleBuffer) {
        guard let fd = CMSampleBufferGetFormatDescription(sb) else { return }
        if !formatSent, let fmt = CodecParameterSets.extract(from: fd, codec: codec) {
            formatSent = true
            onFormat?(fmt)
        }
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sb) else { return }
        let length = CMBlockBufferGetDataLength(dataBuffer)
        var data = Data(count: length)
        let status = data.withUnsafeMutableBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(dataBuffer, atOffset: 0, dataLength: length, destination: base)
        }
        guard status == noErr else { return }

        var isKeyframe = false
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [CFDictionary],
           let first = attachments.first {
            let notSync = CFDictionaryGetValue(first, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
            isKeyframe = notSync == nil
        }
        onFrame?(VideoFrameMessage(
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sb),
            isKeyframe: isKeyframe, data: data))
    }
}
