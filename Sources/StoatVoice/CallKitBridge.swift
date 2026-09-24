import Foundation
import AVFoundation
import CallKit
import LiveKit
import StoatCore
import UIKit

/// With CallKit the system owns the audio session, so LiveKit's audio engine may only run
/// between `didActivate` and `didDeactivate`.
@MainActor
final class CallKitBridge: NSObject {
    enum SystemAction {
        case answer(UUID)
        case end(UUID)
        case setMuted(UUID, Bool)
    }

    var onAction: ((SystemAction) -> Void)?
    private(set) var isAudioActive = false

    private let provider: CXProvider?
    private let controller = CXCallController()

    /// CallKit isn't allowed for apps in mainland China, where calls use Yuki's own screens.
    static var isSupported: Bool {
        Locale.current.region?.identifier != "CN"
    }

    override init() {
        if Self.isSupported {
            let configuration = CXProviderConfiguration()
            configuration.supportsVideo = false
            configuration.maximumCallGroups = 1
            configuration.maximumCallsPerCallGroup = 1
            configuration.supportedHandleTypes = [.generic]
            configuration.includesCallsInRecents = false
            configuration.iconTemplateImageData = UIImage(systemName: "snowflake", withConfiguration: UIImage.SymbolConfiguration(pointSize: 40))?.pngData()
            provider = CXProvider(configuration: configuration)
        } else {
            provider = nil
        }
        super.init()
        provider?.setDelegate(self, queue: nil)
    }

    var isAvailable: Bool { provider != nil }

    func startCall(_ uuid: UUID, title: String) async throws {
        guard let provider else { throw CXErrorCodeRequestTransactionError(.unknownCallProvider) }
        let action = CXStartCallAction(call: uuid, handle: CXHandle(type: .generic, value: title))
        try await controller.request(CXTransaction(action: action))
        let update = CXCallUpdate()
        update.localizedCallerName = title
        update.remoteHandle = CXHandle(type: .generic, value: title)
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        provider.reportCall(with: uuid, updated: update)
    }

    func reportConnected(_ uuid: UUID) {
        provider?.reportOutgoingCall(with: uuid, connectedAt: Date())
    }

    func requestEnd(_ uuid: UUID) {
        controller.request(CXTransaction(action: CXEndCallAction(call: uuid))) { _ in }
    }

    func reportEnded(_ uuid: UUID, reason: CXCallEndedReason) {
        provider?.reportCall(with: uuid, endedAt: Date(), reason: reason)
    }

    func requestMuted(_ uuid: UUID, muted: Bool) {
        controller.request(CXTransaction(action: CXSetMutedCallAction(call: uuid, muted: muted))) { _ in }
    }

    func reportIncoming(_ uuid: UUID, callerName: String) async throws {
        guard let provider else { throw CXErrorCodeIncomingCallError(.unknown) }
        let update = CXCallUpdate()
        update.localizedCallerName = callerName
        update.remoteHandle = CXHandle(type: .generic, value: callerName)
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        try await provider.reportNewIncomingCall(with: uuid, update: update)
    }
}

// The provider's delegate queue is the main queue, so these callbacks run on the main actor.
extension CallKitBridge: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        MainActor.assumeIsolated {
            isAudioActive = false
            try? AudioManager.shared.setEngineAvailability(.none)
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        nonisolated(unsafe) let provider = provider
        nonisolated(unsafe) let action = action
        MainActor.assumeIsolated {
            provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        nonisolated(unsafe) let action = action
        MainActor.assumeIsolated {
            onAction?(.answer(action.callUUID))
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        nonisolated(unsafe) let action = action
        MainActor.assumeIsolated {
            onAction?(.end(action.callUUID))
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        nonisolated(unsafe) let action = action
        MainActor.assumeIsolated {
            onAction?(.setMuted(action.callUUID, action.isMuted))
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        nonisolated(unsafe) let audioSession = audioSession
        MainActor.assumeIsolated {
            do {
                if #available(iOS 26.0, *) {
                    try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .defaultToSpeaker])
                } else {
                    try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
                }
                try AudioManager.shared.setEngineAvailability(.default)
                isAudioActive = true
            } catch {
                DiagnosticsLog.log(.voice, "CallKit audio failed to start: \(error)")
            }
        }
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        MainActor.assumeIsolated {
            isAudioActive = false
            try? AudioManager.shared.setEngineAvailability(.none)
        }
    }
}
