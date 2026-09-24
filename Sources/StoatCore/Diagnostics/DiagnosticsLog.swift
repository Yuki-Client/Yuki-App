import Foundation
import UIKit

// Holds no message text, names or email addresses: people paste this into bug reports.
@MainActor
@Observable
public final class DiagnosticsLog {
    public static let shared = DiagnosticsLog()

    public enum Category: String, Sendable, CaseIterable {
        case app = "App"
        case gateway = "Connection"
        case network = "Network"
        case voice = "Voice"
        case error = "Error"

        public var systemImage: String {
            switch self {
            case .app: "iphone"
            case .gateway: "antenna.radiowaves.left.and.right"
            case .network: "network"
            case .voice: "phone"
            case .error: "exclamationmark.triangle"
            }
        }
    }

    public struct Entry: Identifiable, Sendable {
        public let id = UUID()
        public let date: Date
        public let category: Category
        public let message: String
    }

    /// Newest first.
    public private(set) var entries: [Entry] = []
    private static let limit = 300

    private init() {}

    public func record(_ category: Category, _ message: String) {
        entries.insert(Entry(date: Date(), category: category, message: message), at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
        #if DEBUG
        print("[\(category.rawValue)] \(message)")
        #endif
    }

    public nonisolated static func log(_ category: Category, _ message: String) {
        Task { @MainActor in
            DiagnosticsLog.shared.record(category, message)
        }
    }

    public func clear() {
        entries = []
    }

    public func export() -> String {
        var lines: [String] = ["Yuki diagnostics", deviceSummary, ""]
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        for entry in entries {
            lines.append("\(formatter.string(from: entry.date)) [\(entry.category.rawValue)] \(entry.message)")
        }
        return lines.joined(separator: "\n")
    }

    public var deviceSummary: String {
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let system = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        let model = UIDevice.current.model
        return "Yuki \(version) (\(build)) · \(model) · \(system) · \(StoatInstance.endpoints.api)"
    }
}
