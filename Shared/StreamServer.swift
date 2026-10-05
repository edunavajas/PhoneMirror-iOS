import Foundation
import Network
#if canImport(UIKit)
import UIKit
#endif

final class StreamClient {
    let connection: NWConnection
    var onClose: (() -> Void)?
    private let queue: DispatchQueue

    init(_ connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    /// Start after `onClose` has been assigned, so an immediate failure is not missed.
    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.onClose?()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func send(_ data: Data, completion: @escaping () -> Void) {
        connection.send(content: data, completion: .contentProcessed { _ in completion() })
    }

    func cancel() { connection.cancel() }
}

final class StreamServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.edunavajas.macmirror.server")
    private var clients: [StreamClient] = []
    private var cachedFormat: VideoFormatMessage?
    private var cachedKeyframe: VideoFrameMessage?
    private var inFlight = 0
    private let maxInFlight = 3

    var onClientCountChanged: ((Int) -> Void)?
    var onClientConnected: (() -> Void)?
    var onError: ((String) -> Void)?
    var onPortReady: ((UInt16) -> Void)?

    private static var serviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return UIDevice.current.name
        #endif
    }

    func start(port: UInt16 = 7777) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener: NWListener
        if port == 0 {
            // Any free port; Bonjour advertises the real one, so callers never collide.
            listener = try NWListener(using: params)
        } else {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                throw NSError(domain: "MacMirror", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid port \(port)"])
            }
            listener = try NWListener(using: params, on: nwPort)
        }
        listener.service = NWListener.Service(
            name: Self.serviceName,
            type: MirrorService.type)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let p = self?.listener?.port?.rawValue { self?.onPortReady?(p) }
            case .failed(let error):
                self?.onError?("listener failed: \(error)")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            let client = StreamClient(connection, queue: self.queue)
            self.queue.async {
                client.onClose = { [weak self] in self?.remove(client) }
                self.clients.append(client)
                client.start()
                if let fmt = self.cachedFormat { self.sendFormat(fmt, to: client) }
                // Give the new viewer the current picture immediately, even if the
                // screen is idle and no fresh frame is coming.
                if let keyframe = self.cachedKeyframe { self.sendFrame(keyframe, to: client) }
                self.onClientCountChanged?(self.clients.count)
                self.onClientConnected?()
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        queue.async {
            self.clients.forEach { $0.cancel() }
            self.clients.removeAll()
            self.listener?.cancel()
            self.listener = nil
            self.cachedFormat = nil
            self.cachedKeyframe = nil
            self.inFlight = 0
            self.onClientCountChanged?(0)
        }
    }

    func publish(format: VideoFormatMessage) {
        queue.async {
            self.cachedFormat = format
            self.clients.forEach { self.sendFormat(format, to: $0) }
        }
    }

    func publish(frame: VideoFrameMessage) {
        queue.async {
            if frame.isKeyframe { self.cachedKeyframe = frame }
            guard !self.clients.isEmpty else { return }
            // ponytail: fixed in-flight window bounds latency on LAN; a paced sender
            // or WebRTC congestion control is the upgrade if this ever hits bandwidth.
            if self.inFlight >= self.maxInFlight && !frame.isKeyframe { return }
            self.inFlight += 1
            let snapshot = self.clients
            var remaining = snapshot.count
            for client in snapshot {
                self.sendFrame(frame, to: client) {
                    remaining -= 1
                    if remaining == 0 { self.inFlight -= 1 }
                }
            }
        }
    }

    private func sendFrame(_ frame: VideoFrameMessage, to client: StreamClient, completion: @escaping () -> Void = {}) {
        let payload = frame.encoded()
        let header = MessageHeader(type: .videoFrame, length: UInt32(payload.count)).encoded()
        client.send(header + payload, completion: completion)
    }

    private func sendFormat(_ format: VideoFormatMessage, to client: StreamClient) {
        let payload = format.encoded()
        let header = MessageHeader(type: .videoFormat, length: UInt32(payload.count)).encoded()
        client.send(header + payload) {}
    }

    private func remove(_ client: StreamClient) {
        queue.async {
            self.clients.removeAll { $0 === client }
            self.onClientCountChanged?(self.clients.count)
        }
    }
}
