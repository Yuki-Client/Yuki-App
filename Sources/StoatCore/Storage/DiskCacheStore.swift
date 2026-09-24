import Foundation

/// Atomic disk storage for snapshots of local state, kept out of backups and
/// protected until the device is first unlocked.
public actor DiskCacheStore {
    public static let shared = DiskCacheStore()

    private let fileManager = FileManager.default
    private let directoryURL: URL
    // iOS limits how much an app may write in a day, so an unchanged snapshot isn't written again.
    private var lastSavedHashes: [String: Int] = [:]

    public init() {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        var directory = base.appendingPathComponent("chat.yuki.ios", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        self.directoryURL = directory

        // Earlier builds wrote the cache to Application Support, which is backed up.
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? fileManager.removeItem(at: appSupport.appendingPathComponent("chat.yuki.ios/store_cache.json"))
        }
    }

    public func save(data: Data, filename: String = "store_cache.json") {
        let hash = data.hashValue
        guard lastSavedHashes[filename] != hash else { return }
        let fileURL = directoryURL.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            lastSavedHashes[filename] = hash
        } catch {
            DiagnosticsLog.log(.app, "Couldn't save \(filename): \(error)")
        }
    }

    public func save<T: Encodable & Sendable>(_ object: T, filename: String = "store_cache.json") {
        do {
            save(data: try JSONEncoder().encode(object), filename: filename)
        } catch {
            DiagnosticsLog.log(.app, "Couldn't encode \(filename): \(error)")
        }
    }

    public func load<T: Decodable & Sendable>(filename: String = "store_cache.json") -> T? {
        let fileURL = directoryURL.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            DiagnosticsLog.log(.app, "Discarding unreadable \(filename): \(error)")
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
    }

    public func clear(filename: String = "store_cache.json") {
        let fileURL = directoryURL.appendingPathComponent(filename)
        try? fileManager.removeItem(at: fileURL)
    }
}
