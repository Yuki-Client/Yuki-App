import Foundation
import StoatCore

public enum OverrideState: Sendable, Hashable {
    case allow
    case neutral
    case deny
}

/// Bits the editor doesn't know about are left untouched.
public struct PermissionOverrideValue: Sendable, Hashable {
    public var allow: Int64
    public var deny: Int64

    public init(allow: Int64 = 0, deny: Int64 = 0) {
        self.allow = allow
        self.deny = deny
    }

    public init(_ permissions: RolePermissions?) {
        self.init(allow: permissions?.a ?? 0, deny: permissions?.d ?? 0)
    }

    public func state(of permission: Permission) -> OverrideState {
        if allow & permission.rawValue == permission.rawValue { return .allow }
        if deny & permission.rawValue == permission.rawValue { return .deny }
        return .neutral
    }

    public mutating func set(_ permission: Permission, to state: OverrideState) {
        allow &= ~permission.rawValue
        deny &= ~permission.rawValue
        switch state {
        case .allow: allow |= permission.rawValue
        case .deny: deny |= permission.rawValue
        case .neutral: break
        }
    }

    public var allowedCount: Int { allow.nonzeroBitCount }
    public var deniedCount: Int { deny.nonzeroBitCount }
    public var isEmpty: Bool { allow == 0 && deny == 0 }
}

extension NormalizedStore {
    /// Roles ordered most important first (rank 0 is the top role).
    public func rolesByRank(serverId: String) -> [(id: String, role: Role)] {
        (servers[serverId]?.roles ?? [:])
            .map { (id: $0.key, role: $0.value) }
            .sorted { $0.role.rank == $1.role.rank ? $0.id < $1.id : $0.role.rank < $1.role.rank }
    }

    /// Whether a role sits below the current user's top role. Owners outrank every role.
    public func outranksRole(_ roleId: String, serverId: String) -> Bool {
        guard let userId = currentUserId, let role = servers[serverId]?.roles[roleId] else { return false }
        return role.rank > memberRanking(userId: userId, in: serverId)
    }

    public func canEditRole(_ roleId: String, serverId: String) -> Bool {
        guard let server = servers[serverId], permissions(in: server).contains(.manageRole) else { return false }
        return outranksRole(roleId, serverId: serverId)
    }
}

extension AppStore {
    /// Moves elements like `Array.move(fromOffsets:toOffset:)`, which isn't available outside SwiftUI.
    public static func reorder<T>(_ items: [T], from source: IndexSet, to destination: Int) -> [T] {
        let moving = source.sorted().map { items[$0] }
        var result = items.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        result.insert(contentsOf: moving, at: min(max(0, insertAt), result.count))
        return result
    }

    public func rolesByRank(serverId: String) -> [(id: String, role: Role)] {
        store.rolesByRank(serverId: serverId)
    }

    public func outranksRole(_ roleId: String, serverId: String) -> Bool {
        store.outranksRole(roleId, serverId: serverId)
    }

    public func canEditRole(_ roleId: String, serverId: String) -> Bool {
        store.canEditRole(roleId, serverId: serverId)
    }

    /// Whether a new role order keeps every role the user can't edit in its current position,
    /// which the server requires for anyone but the owner.
    public static func isValidRoleOrder(current: [String], proposed: [String], locked: Set<String>) -> Bool {
        guard current.count == proposed.count, Set(current) == Set(proposed) else { return false }
        return locked.allSatisfy { current.firstIndex(of: $0) == proposed.firstIndex(of: $0) }
    }

    public func createRole(name: String, serverId: String) async -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let response = try await apiClient.createRole(serverId: serverId, name: String(trimmed.prefix(32)))
            store.servers[serverId]?.roles[response.id] = response.role
            return response.id
        } catch {
            showError(error)
            return nil
        }
    }

    /// Updates a role's appearance. Pass `colour: .some(nil)` to clear the colour.
    public func updateRole(roleId: String, serverId: String, name: String?, colour: String??, hoist: Bool?) async -> Bool {
        var payload = DeltaAPIClient.EditRolePayload(name: name, hoist: hoist)
        if let colour {
            if let colour, !colour.isEmpty {
                payload.colour = colour
            } else {
                payload.remove = ["Colour"]
            }
        }
        do {
            let role = try await apiClient.editRole(serverId: serverId, roleId: roleId, payload)
            store.servers[serverId]?.roles[roleId] = role
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func deleteRole(roleId: String, serverId: String) async -> Bool {
        do {
            try await apiClient.deleteRole(serverId: serverId, roleId: roleId)
            store.servers[serverId]?.roles.removeValue(forKey: roleId)
            if var members = store.members[serverId] {
                for (userId, member) in members where member.roles.contains(roleId) {
                    members[userId]?.roles.removeAll { $0 == roleId }
                }
                store.members[serverId] = members
            }
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func setRoleOrder(_ order: [String], serverId: String) async -> Bool {
        guard let previous = store.servers[serverId] else { return false }
        let current = rolesByRank(serverId: serverId).map(\.id)
        if previous.owner != store.currentUserId {
            let locked = Set(current.filter { !canEditRole($0, serverId: serverId) })
            guard Self.isValidRoleOrder(current: current, proposed: order, locked: locked) else {
                showError("You can only reorder roles ranked below your highest role.")
                return false
            }
        }

        var optimistic = previous
        for (index, roleId) in order.enumerated() {
            optimistic.roles[roleId]?.rank = Int64(index)
        }
        store.servers[serverId] = optimistic

        do {
            let updated = try await apiClient.editRoleRanks(serverId: serverId, ranks: order)
            store.servers[serverId] = updated
            return true
        } catch {
            store.servers[serverId] = previous
            showError(error)
            return false
        }
    }

    public func setRolePermissions(_ value: PermissionOverrideValue, roleId: String, serverId: String) async -> Bool {
        do {
            let updated = try await apiClient.setServerRolePermissions(
                serverId: serverId,
                roleId: roleId,
                .init(allow: value.allow, deny: value.deny)
            )
            store.servers[serverId] = updated
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func setDefaultPermissions(_ permissions: Int64, serverId: String) async -> Bool {
        do {
            store.servers[serverId] = try await apiClient.setServerDefaultPermissions(serverId: serverId, permissions: permissions)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    /// Sets a channel override for a role, or the channel's default override when `roleId` is nil.
    public func setChannelPermissions(_ value: PermissionOverrideValue, roleId: String?, channelId: String) async -> Bool {
        do {
            let payload = DeltaAPIClient.PermissionOverridePayload(allow: value.allow, deny: value.deny)
            let updated: Channel
            if let roleId {
                updated = try await apiClient.setChannelRolePermissions(channelId: channelId, roleId: roleId, payload)
            } else {
                updated = try await apiClient.setChannelDefaultPermissions(channelId: channelId, payload)
            }
            store.channels[channelId] = updated
            scheduleCacheSave()
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func setGroupPermissions(_ permissions: Int64, channelId: String) async -> Bool {
        do {
            store.channels[channelId] = try await apiClient.setGroupPermissions(channelId: channelId, permissions: permissions)
            scheduleCacheSave()
            return true
        } catch {
            showError(error)
            return false
        }
    }

    /// Generates a category ID in the same ULID format Stoat for Web uses.
    public static func makeCategoryId() -> String {
        makeNonce()
    }

    /// Removes channels that no longer exist and any channel listed in more than one category,
    /// which the server rejects.
    public static func sanitizedCategories(_ categories: [ServerCategory], serverChannels: [String]) -> [ServerCategory] {
        let known = Set(serverChannels)
        var seen = Set<String>()
        return categories.map { category in
            var copy = category
            copy.title = String(category.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
            copy.channels = category.channels.filter { known.contains($0) && seen.insert($0).inserted }
            return copy
        }
    }

    public func createChannel(serverId: String, name: String, type: ChannelType, description: String?, categoryId: String?) async -> Channel? {
        guard let channel = await createChannel(serverId: serverId, name: name, type: type, description: description) else { return nil }
        if let categoryId, var categories = store.servers[serverId]?.categories,
           let index = categories.firstIndex(where: { $0.id == categoryId }) {
            categories[index].channels.append(channel.id)
            _ = await updateCategories(serverId: serverId, categories: categories)
        }
        return channel
    }
}
