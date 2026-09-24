import Foundation
import Network

public actor GatewayClient {
    public enum ConnectionState: Sendable, Equatable {
        case disconnected
        case connecting
        case connected
        case authenticated
    }

    private let wsURL: URL
    private let token: String

    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var heartbeatTask: Task<Void, Never>?
    private var listenerTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var connectTimeoutTask: Task<Void, Never>?
    private var resumeCheckTask: Task<Void, Never>?

    /// Incremented for every connection attempt so callbacks from old sockets are ignored.
    private var generation = 0
    private var failedAttempts = 0
    private var isIntentionallyClosed = false
    private var lastReceivedAt = Date.distantPast
    private var lastPingSentAt: Date?
    private var openedAt: Date?
    private var pathMonitor: NWPathMonitor?

    public private(set) var state: ConnectionState = .disconnected

    private let continuation: AsyncStream<GatewayEvent>.Continuation
    public nonisolated let events: AsyncStream<GatewayEvent>

    private let stateContinuation: AsyncStream<ConnectionState>.Continuation
    public nonisolated let connectionStates: AsyncStream<ConnectionState>

    private static let heartbeatInterval: TimeInterval = 20
    /// The connection is considered dead after this long without receiving anything,
    /// which spans two unanswered pings rather than one slow one.
    private static let silenceTimeout: TimeInterval = 50
    private static let connectTimeout: TimeInterval = 30

    public init(wsURL: URL, token: String) {
        self.wsURL = wsURL
        self.token = token
        (events, continuation) = AsyncStream.makeStream(of: GatewayEvent.self, bufferingPolicy: .unbounded)
        (connectionStates, stateContinuation) = AsyncStream.makeStream(of: ConnectionState.self, bufferingPolicy: .bufferingNewest(8))
    }

    private func setState(_ newState: ConnectionState) {
        guard state != newState else { return }
        state = newState
        stateContinuation.yield(newState)
    }

    private func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        let time = Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits).secondFraction(.fractional(3)))
        print("[Gateway \(time) #\(generation)] \(message())")
        #endif
    }

    // MARK: - Lifecycle

    public func connect() {
        guard state == .disconnected else { return }
        isIntentionallyClosed = false
        reconnectTask?.cancel()
        reconnectTask = nil
        startPathMonitorIfNeeded()
        openSocket()
    }

    public func disconnect() {
        isIntentionallyClosed = true
        reconnectTask?.cancel()
        reconnectTask = nil
        teardownSocket(closeCode: .goingAway)
        setState(.disconnected)
    }

    public func shutdown() {
        disconnect()
        pathMonitor?.cancel()
        pathMonitor = nil
        continuation.finish()
        stateContinuation.finish()
    }

    public func reconnect() {
        log("Manual reconnect")
        isIntentionallyClosed = false
        reconnectTask?.cancel()
        reconnectTask = nil
        failedAttempts = 0
        teardownSocket(closeCode: .goingAway)
        setState(.disconnected)
        openSocket()
    }

    // Sockets are usually dead after the app has been suspended.
    public func resumeFromBackground() {
        guard !isIntentionallyClosed else { return }
        let silence = Date().timeIntervalSince(lastReceivedAt)
        switch state {
        case .authenticated where silence < Self.heartbeatInterval:
            sendPing()
        case .authenticated:
            // Reconnecting means downloading everything again, so give the old socket a moment to
            // answer a ping first: after a short trip away it's often still alive.
            log("Resumed after \(Int(silence))s of silence, checking the socket")
            let resumedAt = Date()
            let checkedGeneration = generation
            sendPing()
            resumeCheckTask?.cancel()
            resumeCheckTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                await self?.finishResumeCheck(since: resumedAt, generation: checkedGeneration)
            }
        case .connecting, .connected:
            // A connection attempt is already underway; let it finish or time out.
            break
        case .disconnected:
            reconnectTask?.cancel()
            reconnectTask = nil
            failedAttempts = 0
            openSocket()
        }
    }

    private func finishResumeCheck(since resumedAt: Date, generation checkedGeneration: Int) {
        resumeCheckTask = nil
        guard checkedGeneration == generation, state == .authenticated, lastReceivedAt < resumedAt else { return }
        log("No answer after resuming, reconnecting")
        reconnect()
    }

    public func send(command: GatewayCommand) {
        guard let task = webSocketTask, state == .connected || state == .authenticated else { return }
        do {
            let data = try JSONEncoder().encode(command)
            guard let jsonString = String(data: data, encoding: .utf8) else { return }
            task.send(.string(jsonString)) { error in
                if let error {
                    DiagnosticsLog.log(.gateway, "Send failed: \(error.localizedDescription)")
                }
            }
        } catch {
            DiagnosticsLog.log(.error, "Couldn't encode a gateway command: \(error)")
        }
    }

    // MARK: - Socket

    private func openSocket() {
        generation += 1
        let currentGeneration = generation
        setState(.connecting)
        openedAt = nil
        lastPingSentAt = nil
        log("Connecting (attempt \(failedAttempts + 1))")

        var components = URLComponents(url: wsURL, resolvingAgainstBaseURL: false)
        var items = (components?.queryItems ?? []).filter { $0.name != "version" && $0.name != "format" }
        items.append(URLQueryItem(name: "version", value: "1"))
        items.append(URLQueryItem(name: "format", value: "json"))
        components?.queryItems = items

        guard let targetURL = components?.url else {
            setState(.disconnected)
            return
        }

        let delegate = GatewaySocketDelegate(client: self, generation: currentGeneration)
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        // For WebSocket tasks this acts as an idle timeout between frames, so keep it well above the heartbeat.
        configuration.timeoutIntervalForRequest = 300
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.webSocketTask(with: targetURL)
        // Ready payloads for large accounts easily exceed the 1 MB default.
        task.maximumMessageSize = 64 * 1024 * 1024
        self.session = session
        self.webSocketTask = task
        task.resume()

        startListening(task: task, generation: currentGeneration)

        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.connectTimeout))
            guard !Task.isCancelled else { return }
            await self?.handleConnectTimeout(generation: currentGeneration)
        }
    }

    private func teardownSocket(closeCode: URLSessionWebSocketTask.CloseCode) {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        resumeCheckTask?.cancel()
        resumeCheckTask = nil
        listenerTask?.cancel()
        listenerTask = nil
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        webSocketTask?.cancel(with: closeCode, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        lastPingSentAt = nil
    }

    fileprivate func handleOpen(generation openedGeneration: Int) {
        guard openedGeneration == generation, state == .connecting else { return }
        openedAt = Date()
        lastReceivedAt = Date()
        log("Socket open, authenticating")
        setState(.connected)
        send(command: .authenticate(token: token))
        startHeartbeat(generation: openedGeneration)
    }

    fileprivate func handleClose(generation closedGeneration: Int, code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard closedGeneration == generation else { return }
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        handleFailure(generation: closedGeneration, reason: "server closed (code \(code.rawValue)\(reasonText.isEmpty ? "" : ": \(reasonText)"))")
    }

    fileprivate func handleTaskError(generation failedGeneration: Int, error: Error) {
        guard failedGeneration == generation else { return }
        handleFailure(generation: failedGeneration, reason: "task failed: \(error.localizedDescription)")
    }

    private func handleConnectTimeout(generation timedOutGeneration: Int) {
        guard timedOutGeneration == generation, state != .authenticated else { return }
        let stage = openedAt == nil ? "socket never opened" : "no Authenticated event"
        handleFailure(generation: timedOutGeneration, reason: "connect timed out (\(stage))")
    }

    private func handleFailure(generation failedGeneration: Int, reason: String) {
        guard failedGeneration == generation, webSocketTask != nil || state != .disconnected else { return }
        let uptime = openedAt.map { " after \(Int(Date().timeIntervalSince($0)))s" } ?? ""
        DiagnosticsLog.log(.gateway, "Connection lost\(uptime): \(reason)")
        teardownSocket(closeCode: .abnormalClosure)
        setState(.disconnected)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !isIntentionallyClosed, reconnectTask == nil else { return }
        failedAttempts += 1
        let base = min(30.0, pow(2.0, Double(failedAttempts)) - 1)
        let delay = max(0.5, base * Double.random(in: 0.8...1.2))
        log("Reconnecting in \(String(format: "%.1f", delay))s")
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.performScheduledReconnect()
        }
    }

    private func performScheduledReconnect() {
        reconnectTask = nil
        guard !isIntentionallyClosed, state == .disconnected else { return }
        openSocket()
    }

    // MARK: - Loops

    private func startHeartbeat(generation heartbeatGeneration: Int) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.heartbeatInterval))
                guard !Task.isCancelled, let self else { break }
                await self.heartbeat(generation: heartbeatGeneration)
            }
        }
    }

    private func heartbeat(generation heartbeatGeneration: Int) {
        guard heartbeatGeneration == generation else { return }
        let silence = Date().timeIntervalSince(lastReceivedAt)
        if silence > Self.silenceTimeout {
            handleFailure(generation: heartbeatGeneration, reason: "nothing received for \(Int(silence))s")
            return
        }
        sendPing()
    }

    private func sendPing() {
        lastPingSentAt = Date()
        send(command: .ping(data: Int(Date().timeIntervalSince1970 * 1000)))
    }

    private func startListening(task: URLSessionWebSocketTask, generation listenGeneration: Int) {
        listenerTask?.cancel()
        listenerTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    guard let self else { break }
                    switch message {
                    case .string(let text):
                        await self.handleIncomingData(Data(text.utf8), generation: listenGeneration)
                    case .data(let data):
                        await self.handleIncomingData(data, generation: listenGeneration)
                    @unknown default:
                        break
                    }
                } catch {
                    guard !Task.isCancelled else { break }
                    let closeCode = task.closeCode.rawValue
                    await self?.handleFailure(generation: listenGeneration, reason: "\(error.localizedDescription) (close code \(closeCode))")
                    break
                }
            }
        }
    }

    private func handleIncomingData(_ data: Data, generation dataGeneration: Int) {
        guard dataGeneration == generation else { return }
        lastReceivedAt = Date()

        let started = Date()
        let event: GatewayEvent
        do {
            event = try JSONDecoder().decode(GatewayEvent.self, from: data)
        } catch {
            DiagnosticsLog.log(.gateway, "Couldn't decode a packet: \(error)")
            return
        }

        switch event {
        case .authenticated:
            log("Authenticated")
            setState(.authenticated)
            connectTimeoutTask?.cancel()
        case .ready(let ready):
            log("Ready: \(data.count / 1024) KB decoded in \(Int(Date().timeIntervalSince(started) * 1000)) ms, \(ready.servers.count) servers, \(ready.channels.count) channels, \(ready.users.count) users")
            setState(.authenticated)
            connectTimeoutTask?.cancel()
            failedAttempts = 0
        case .pong:
            if let sent = lastPingSentAt {
                let latency = Int(Date().timeIntervalSince(sent) * 1000)
                if latency > 2000 {
                    log("Slow pong: \(latency) ms")
                }
            }
        case .logout:
            log("Logged out by server")
            isIntentionallyClosed = true
        case .error(let type):
            log("Error event: \(type)")
            if type == "InvalidSession" || type == "NotAuthenticated" {
                isIntentionallyClosed = true
            }
        default:
            break
        }

        continuation.yield(event)

        if isIntentionallyClosed {
            teardownSocket(closeCode: .normalClosure)
            setState(.disconnected)
        }
    }

    // MARK: - Network changes

    private func startPathMonitorIfNeeded() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { await self?.handlePathUpdate(satisfied: satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "chat.yuki.gateway.path"))
        pathMonitor = monitor
    }

    private func handlePathUpdate(satisfied: Bool) {
        guard satisfied, !isIntentionallyClosed else { return }
        switch state {
        case .disconnected:
            log("Network available, reconnecting now")
            reconnectTask?.cancel()
            reconnectTask = nil
            failedAttempts = 0
            openSocket()
        case .authenticated:
            // The route may have changed (e.g. Wi-Fi to cellular); probe the existing socket.
            sendPing()
        case .connecting, .connected:
            break
        }
    }
}

private final class GatewaySocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private weak var client: GatewayClient?
    private let generation: Int

    init(client: GatewayClient, generation: Int) {
        self.client = client
        self.generation = generation
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        let generation = generation
        Task { [client] in await client?.handleOpen(generation: generation) }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let generation = generation
        Task { [client] in await client?.handleClose(generation: generation, code: closeCode, reason: reason) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (error as? URLError)?.code != .cancelled else { return }
        let generation = generation
        Task { [client] in await client?.handleTaskError(generation: generation, error: error) }
    }
}
