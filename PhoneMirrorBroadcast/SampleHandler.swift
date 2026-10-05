import ReplayKit
import Foundation
import CoreMedia
import CoreVideo

/// Runs in the Broadcast Upload Extension. ReplayKit hands us the whole screen;
/// we hardware-encode it and stream it to the Mac over Bonjour.
final class SampleHandler: RPBroadcastSampleHandler {
    private let server = StreamServer()
    private var encoder: VideoEncoder?
    private var started = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        MirrorService.type = "_phonemirror._tcp"
        server.onError = { message in NSLog("PhoneMirror server: %@", message) }
        do {
            try server.start(port: 0)
            started = true
        } catch {
            finishBroadcastWithError(error)
        }
    }

    override func broadcastPaused() {
        // Keep the encoder; dropping frames while paused is fine.
    }

    override func broadcastResumed() {}

    override func broadcastFinished() {
        server.stop()
        encoder?.invalidate()
        encoder = nil
        started = false
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard started, sampleBufferType == .video, sampleBuffer.isValid else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if encoder == nil {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            // HEVC for sharper text at the same bitrate; fall back to H.264 if the
            // device refuses an HEVC session.
            var enc = VideoEncoder(width: Int32(width), height: Int32(height), fps: 30,
                                   codec: .hevc, bitrate: 12_000_000)
            if !enc.isReady {
                enc = VideoEncoder(width: Int32(width), height: Int32(height), fps: 30,
                                   codec: .h264, bitrate: 12_000_000)
            }
            enc.onFormat = { [weak self] format in self?.server.publish(format: format) }
            enc.onFrame = { [weak self] frame in self?.server.publish(frame: frame) }
            enc.onError = { message in NSLog("PhoneMirror encoder: %@", message) }
            server.onClientConnected = { [weak enc] in enc?.forceKeyframe() }
            encoder = enc
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        encoder?.encode(pixelBuffer, pts: pts)
    }
}
