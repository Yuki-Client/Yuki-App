import Foundation
import StoatCore

public enum SidebarEntry: Identifiable, Sendable {
    case server(Server)
    case folder(ServerFolder, servers: [Server])

    public var id: String {
        switch self {
        case .server(let server): server.id
        case .folder(let folder, _): folder.id
        }
    }

    public var servers: [Server] {
        switch self {
        case .server(let server): [server]
        case .folder(_, let servers): servers
        }
    }
}

/// Where servers and folders sit in the server list, worked out the same way as Stoat for Web
/// so both show the same thing. Every change returns a new layout to store and sync.
public struct ServerSidebarLayout: Sendable, Equatable {
    /// Server and folder IDs, each folder followed by its members.
    public var order: [String]
    public var folders: [ServerFolder]

    public init(order: [String], folders: [ServerFolder]) {
        self.order = order
        self.folders = folders
    }

    /// A folder is drawn where its ID sits in the order, or else where its first member does, and
    /// only if it has servers the user is in. Servers not in the order go at the end.
    public func entries(servers: [String: Server]) -> [SidebarEntry] {
        var known = Set(servers.keys)
        var byId: [String: ServerFolder] = [:]
        var folderOf: [String: ServerFolder] = [:]
        for folder in folders {
            byId[folder.id] = folder
            for serverId in folder.servers where folderOf[serverId] == nil {
                folderOf[serverId] = folder
            }
        }

        var out: [SidebarEntry] = []
        var drawn = Set<String>()
        func take(_ id: String) {
            if let folder = byId[id] ?? folderOf[id] {
                guard drawn.insert(folder.id).inserted else { return }
                let members = folder.servers.compactMap { known.remove($0) != nil ? servers[$0] : nil }
                if !members.isEmpty {
                    out.append(.folder(folder, servers: members))
                }
                return
            }
            if known.remove(id) != nil, let server = servers[id] {
                out.append(.server(server))
            }
        }
        order.forEach(take)
        known.sorted().forEach(take)
        return out
    }

    public func folder(containing serverId: String) -> ServerFolder? {
        folders.first { $0.servers.contains(serverId) }
    }

    public func folder(id: String) -> ServerFolder? {
        folders.first { $0.id == id }
    }

    public func creatingFolder(id: String, name: String, serverIds: [String], servers: [String: Server]) -> Self {
        var top = topLevel(servers)
        let claimed = Set(serverIds)
        let position = serverIds.lazy.compactMap { self.topLevelIndex(of: $0, in: top) }.first ?? top.count
        let before = top.prefix(position).filter { !claimed.contains($0) }
        let after = top.dropFirst(position).filter { !claimed.contains($0) }
        top = before + [id] + after
        let folders = removing(claimed, from: self.folders) + [ServerFolder(id: id, name: name, servers: serverIds)]
        return rebuilt(top, folders)
    }

    public func editingFolder(_ id: String, _ change: (inout ServerFolder) -> Void) -> Self {
        var copy = self
        if let index = copy.folders.firstIndex(where: { $0.id == id }) {
            change(&copy.folders[index])
        }
        return copy
    }

    public func deletingFolder(_ id: String, servers: [String: Server]) -> Self {
        let entries = entries(servers: servers)
        let top = entries.flatMap { entry -> [String] in
            entry.id == id ? entry.servers.map(\.id) : [entry.id]
        }
        return rebuilt(top, folders.filter { $0.id != id })
    }

    public func addingServer(_ serverId: String, toFolder folderId: String, before: String? = nil, servers: [String: Server]) -> Self {
        var top = topLevel(servers)
        let oldIndex = topLevelIndex(of: serverId, in: top)
        top.removeAll { $0 == serverId }
        if !top.contains(folderId) {
            top.insert(folderId, at: min(oldIndex ?? top.count, top.count))
        }
        var folders = removing([serverId], from: self.folders)
        if let index = folders.firstIndex(where: { $0.id == folderId }) {
            var members = folders[index].servers
            let at = before.flatMap { members.firstIndex(of: $0) } ?? members.count
            members.insert(serverId, at: at)
            folders[index].servers = members
        }
        return rebuilt(top, folders)
    }

    /// Takes a server out of its folder and puts it just below the folder.
    public func removingServerFromFolder(_ serverId: String, servers: [String: Server]) -> Self {
        guard let folder = folder(containing: serverId) else { return self }
        var top = topLevel(servers)
        let index = top.firstIndex(of: folder.id).map { $0 + 1 } ?? top.count
        top.insert(serverId, at: index)
        return rebuilt(top, removing([serverId], from: folders))
    }

    /// Moves a dragged server or folder to where another server or folder is. A server dropped on
    /// a folder goes inside it, and one dropped on a server in a folder joins that folder.
    public func moving(_ id: String, onto targetId: String, servers: [String: Server]) -> Self? {
        guard id != targetId else { return nil }
        let targetFolder = ServerFolder.isFolderId(targetId) ? folder(id: targetId) : folder(containing: targetId)

        if ServerFolder.isFolderId(id) {
            return movingTopLevel(id, onto: targetFolder?.id ?? targetId, servers: servers)
        }
        if ServerFolder.isFolderId(targetId) {
            guard folder(containing: id)?.id != targetId else { return nil }
            return addingServer(id, toFolder: targetId, servers: servers)
        }
        if let targetFolder {
            if folder(containing: id)?.id == targetFolder.id {
                return editingFolder(targetFolder.id) { folder in
                    folder.servers = Self.move(id, onto: targetId, in: folder.servers)
                }
                .refreshed(servers)
            }
            return addingServer(id, toFolder: targetFolder.id, before: targetId, servers: servers)
        }
        if folder(containing: id) != nil {
            var top = topLevel(servers)
            top.insert(id, at: top.firstIndex(of: targetId) ?? top.count)
            return rebuilt(top, removing([id], from: folders))
        }
        return movingTopLevel(id, onto: targetId, servers: servers)
    }

    public func movingTopLevel(from source: IndexSet, to destination: Int, servers: [String: Server]) -> Self {
        rebuilt(Self.move(topLevel(servers), from: source, to: destination), folders)
    }

    public func movingInFolder(_ folderId: String, from source: IndexSet, to destination: Int, servers: [String: Server]) -> Self {
        editingFolder(folderId) { folder in
            // Only the servers on screen were moved; any the user has left stay at the end.
            let visible = folder.servers.filter { servers[$0] != nil }
            let hidden = folder.servers.filter { servers[$0] == nil }
            folder.servers = Self.move(visible, from: source, to: destination) + hidden
        }
        .refreshed(servers)
    }

    public func flatServerIds(servers: [String: Server]) -> [String] {
        entries(servers: servers).flatMap { $0.servers.map(\.id) }
    }

    private func topLevel(_ servers: [String: Server]) -> [String] {
        entries(servers: servers).map(\.id)
    }

    private func topLevelIndex(of serverId: String, in top: [String]) -> Int? {
        top.firstIndex(of: serverId) ?? folder(containing: serverId).flatMap { top.firstIndex(of: $0.id) }
    }

    private func movingTopLevel(_ id: String, onto targetId: String, servers: [String: Server]) -> Self? {
        let top = topLevel(servers)
        guard top.contains(id), top.contains(targetId), id != targetId else { return nil }
        return rebuilt(Self.move(id, onto: targetId, in: top), folders)
    }

    private func refreshed(_ servers: [String: Server]) -> Self {
        rebuilt(topLevel(servers), folders)
    }

    private func removing(_ serverIds: Set<String>, from folders: [ServerFolder]) -> [ServerFolder] {
        folders.map { folder in
            var folder = folder
            folder.servers.removeAll { serverIds.contains($0) }
            return folder
        }
    }

    /// Stores each folder followed by its members, so they keep their place if a client that
    /// doesn't know about folders, or one that removes the folder, rewrites the list.
    private func rebuilt(_ top: [String], _ folders: [ServerFolder]) -> Self {
        let kept = folders.filter { !$0.servers.isEmpty }
        let byId = Dictionary(kept.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let order = top.flatMap { id -> [String] in
            if ServerFolder.isFolderId(id) {
                guard let folder = byId[id] else { return [] }
                return [id] + folder.servers
            }
            return [id]
        }
        .filter { seen.insert($0).inserted }
        return ServerSidebarLayout(order: order, folders: kept)
    }

    /// Moves an item to where another is: after it when moving down, in front of it when moving up.
    static func move(_ id: String, onto targetId: String, in list: [String]) -> [String] {
        guard let from = list.firstIndex(of: id), let to = list.firstIndex(of: targetId), from != to else { return list }
        var list = list
        list.remove(at: from)
        let target = list.firstIndex(of: targetId) ?? list.count
        list.insert(id, at: from < to ? target + 1 : target)
        return list
    }

    static func move(_ list: [String], from source: IndexSet, to destination: Int) -> [String] {
        let moving = source.filter { $0 < list.count }.map { list[$0] }
        var rest = list.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: min(max(0, insertAt), rest.count))
        return rest
    }
}
