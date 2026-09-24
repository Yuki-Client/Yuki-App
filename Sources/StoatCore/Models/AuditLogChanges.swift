import Foundation

public enum AuditLogChange: Hashable, Sendable {
    /// A field that was set (`old` nil), changed, or cleared (`new` nil).
    case value(field: String, old: String?, new: String?)
    case added(field: String, item: String)
    case removed(field: String, item: String)
    /// A permission's state, optionally scoped to a role. `old` is nil when Stoat didn't record it.
    case permission(scope: String?, name: String, old: PermissionState?, new: PermissionState)
    case note(String)

    public enum PermissionState: String, Hashable, Sendable {
        case allowed = "Allowed"
        case neutral = "Not set"
        case denied = "Denied"
        case on = "On"
        case off = "Off"
    }
}

public struct AuditLogChangeBuilder {
    public var userName: (String) -> String
    public var roleName: (String) -> String
    public var channelName: (String) -> String

    public init(userName: @escaping (String) -> String, roleName: @escaping (String) -> String, channelName: @escaping (String) -> String) {
        self.userName = userName
        self.roleName = roleName
        self.channelName = channelName
    }

    /// Changes for `entry`. `previous` is the next older entry for the same channel and role,
    /// which supplies the old values Stoat doesn't store for channel permission overrides.
    public func changes(for entry: AuditLogEntry, previous: AuditLogEntry? = nil) -> [AuditLogChange] {
        let action = entry.action
        switch action.type {
        case "ChannelEdit":
            return fieldChanges(action, kind: .channel)
        case "ServerEdit":
            return fieldChanges(action, kind: .server)
        case "RoleEdit":
            return fieldChanges(action, kind: .role)
        case "MemberEdit":
            return fieldChanges(action, kind: .member)
        case "EmojiUpdate":
            return fieldChanges(action, kind: .emoji)
        case "RolesReorder":
            return reorderChanges(before: action.before?.array ?? [], after: action.after?.array ?? [])
        case "ChannelRolePermissionsEdit":
            return channelOverrideChanges(action, previous: previous?.action)
        default:
            return []
        }
    }

    public static func isPreviousOverride(_ candidate: AuditLogEntry, of entry: AuditLogEntry) -> Bool {
        entry.action.type == "ChannelRolePermissionsEdit"
            && candidate.action.type == "ChannelRolePermissionsEdit"
            && candidate.action.channel == entry.action.channel
            && candidate.action.role == entry.action.role
            && candidate.id < entry.id
    }

    // MARK: - Edits

    private enum Kind {
        case channel, server, role, member, emoji
    }

    /// Fields that change on their own and aren't worth showing.
    private static let ignoredFields: Set<String> = ["last_message_id", "active", "approximate_member_count"]

    private func fieldChanges(_ action: AuditLogAction, kind: Kind) -> [AuditLogChange] {
        let before = action.before?.object ?? [:]
        let after = action.after?.object ?? [:]
        let keys = Set(before.keys).union(after.keys).subtracting(Self.ignoredFields)
        return keys.sorted { fieldOrder($0) < fieldOrder($1) }.flatMap { key in
            fieldChange(key, old: before[key], new: after[key], kind: kind)
        }
    }

    private static let order = [
        "name", "nickname", "owner", "description", "pronouns", "roles", "timeout", "colour", "hoist", "rank",
        "nsfw", "slowmode", "voice", "icon", "avatar", "banner", "categories", "system_messages", "channels",
        "permissions", "default_permissions", "role_permissions", "can_publish", "can_receive", "discoverable",
        "analytics", "flags"
    ]

    private func fieldOrder(_ key: String) -> Int {
        Self.order.firstIndex(of: key) ?? Self.order.count
    }

    private func fieldChange(_ key: String, old: JSONValue?, new: JSONValue?, kind: Kind) -> [AuditLogChange] {
        let old = old == .null ? nil : old
        let new = new == .null ? nil : new
        guard old != new else { return [] }

        switch key {
        case "name":
            return [.value(field: "Name", old: old?.string, new: new?.string)]
        case "nickname":
            return [.value(field: "Nickname", old: old?.string, new: new?.string)]
        case "pronouns":
            return [.value(field: "Pronouns", old: old?.string, new: new?.string)]
        case "description":
            return [.value(field: kind == .channel ? "Topic" : "Description", old: old?.string, new: new?.string)]
        case "owner":
            return [.value(field: "Owner", old: old?.string.map(userName), new: new?.string.map(userName))]
        case "colour":
            return [.value(field: "Colour", old: old?.string, new: new?.string)]
        case "hoist":
            return [.value(field: "Shown separately", old: yesNo(old), new: yesNo(new))]
        case "rank":
            return [.value(field: "Position", old: old?.int.map { "\($0)" }, new: new?.int.map { "\($0)" })]
        case "nsfw":
            return [.value(field: "Mature content", old: onOff(old), new: onOff(new))]
        case "discoverable":
            return [.value(field: "Discoverable", old: yesNo(old), new: yesNo(new))]
        case "analytics":
            return [.value(field: "Analytics", old: yesNo(old), new: yesNo(new))]
        case "can_publish":
            return [.value(field: "Can speak in voice", old: yesNo(old), new: yesNo(new))]
        case "can_receive":
            return [.value(field: "Can listen in voice", old: yesNo(old), new: yesNo(new))]
        case "slowmode":
            return [.value(field: "Slowmode", old: Channel.slowmodeLabel(Int(old?.int ?? 0)), new: Channel.slowmodeLabel(Int(new?.int ?? 0)))]
        case "voice":
            let limit = { (value: JSONValue?) -> String in value?["max_users"]?.int.map { "\($0)" } ?? "No limit" }
            return [.value(field: "Voice user limit", old: limit(old), new: limit(new))]
        case "timeout":
            let format = { (value: JSONValue?) -> String? in value?.string.map(Self.formatDate) }
            if new == nil { return [.note("Timeout removed")] }
            return [.value(field: "Timed out until", old: format(old), new: format(new))]
        case "icon", "avatar", "banner":
            let noun = key == "avatar" ? (kind == .member ? "server avatar" : "avatar") : key
            if old == nil { return [.note("Set the \(noun)")] }
            if new == nil { return [.note("Removed the \(noun)")] }
            return [.note("Changed the \(noun)")]
        case "roles":
            return listChanges(field: "Roles", old: old, new: new, name: roleName)
        case "channels":
            return listChanges(field: "Channels", old: old, new: new, name: channelName)
        case "categories":
            return categoryChanges(old: old?.array ?? [], new: new?.array ?? [])
        case "system_messages":
            return systemMessageChanges(old: old?.object ?? [:], new: new?.object ?? [:])
        case "permissions", "default_permissions":
            // Roles and server channels store allow/deny overrides; servers and groups store plain bits.
            let scope = key == "default_permissions" ? "Everyone" : nil
            if kind == .role || (kind == .channel && key == "default_permissions") {
                return overrideChanges(scope: scope, old: Self.override(old), new: Self.override(new) ?? (0, 0))
            }
            return bitfieldChanges(scope: scope, old: old?.int ?? 0, new: new?.int ?? 0)
        case "role_permissions":
            let oldRoles = old?.object ?? [:]
            let newRoles = new?.object ?? [:]
            return Set(oldRoles.keys).union(newRoles.keys).sorted().flatMap { roleId in
                overrideChanges(scope: roleName(roleId), old: Self.override(oldRoles[roleId]) ?? (0, 0), new: Self.override(newRoles[roleId]) ?? (0, 0))
            }
        case "flags":
            return [.value(field: "Flags", old: old?.int.map { "\($0)" }, new: new?.int.map { "\($0)" })]
        default:
            let label = key.replacingOccurrences(of: "_", with: " ").capitalized
            return [.value(field: label, old: old.map(Self.summary), new: new.map(Self.summary))]
        }
    }

    private func listChanges(field: String, old: JSONValue?, new: JSONValue?, name: (String) -> String) -> [AuditLogChange] {
        let oldIds = (old?.array ?? []).compactMap(\.string)
        let newIds = (new?.array ?? []).compactMap(\.string)
        let added = newIds.filter { !oldIds.contains($0) }.map { AuditLogChange.added(field: field, item: name($0)) }
        let removed = oldIds.filter { !newIds.contains($0) }.map { AuditLogChange.removed(field: field, item: name($0)) }
        if added.isEmpty && removed.isEmpty && oldIds != newIds {
            return [.note("Reordered \(field.lowercased())")]
        }
        return added + removed
    }

    private func categoryChanges(old: [JSONValue], new: [JSONValue]) -> [AuditLogChange] {
        func byId(_ list: [JSONValue]) -> [(id: String, title: String, channels: [String])] {
            list.compactMap { category in
                guard let id = category["id"]?.string else { return nil }
                return (id, category["title"]?.string ?? "Category", (category["channels"]?.array ?? []).compactMap(\.string))
            }
        }
        let oldList = byId(old)
        let newList = byId(new)
        var changes: [AuditLogChange] = []

        for category in newList where !oldList.contains(where: { $0.id == category.id }) {
            changes.append(.added(field: "Categories", item: category.title))
        }
        for category in oldList where !newList.contains(where: { $0.id == category.id }) {
            changes.append(.removed(field: "Categories", item: category.title))
        }
        for category in newList {
            guard let before = oldList.first(where: { $0.id == category.id }), before.title != category.title else { continue }
            changes.append(.value(field: "Category name", old: before.title, new: category.title))
        }

        // Where each channel sat before and after, to show moves as one change.
        func homes(_ list: [(id: String, title: String, channels: [String])]) -> [String: (id: String, title: String)] {
            Dictionary(list.flatMap { category in category.channels.map { ($0, (category.id, category.title)) } }, uniquingKeysWith: { first, _ in first })
        }
        let oldHomes = homes(oldList)
        let newHomes = homes(newList)
        let channels = (oldList.flatMap(\.channels) + newList.flatMap(\.channels)).reduce(into: [String]()) { list, id in
            if !list.contains(id) { list.append(id) }
        }
        for channel in channels {
            switch (oldHomes[channel], newHomes[channel]) {
            case let (from?, to?) where from.id != to.id:
                changes.append(.value(field: channelName(channel), old: from.title, new: to.title))
            case let (nil, to?):
                changes.append(.added(field: "Channels in \(to.title)", item: channelName(channel)))
            case let (from?, nil):
                changes.append(.removed(field: "Channels in \(from.title)", item: channelName(channel)))
            default:
                break
            }
        }
        if changes.isEmpty && oldList.map(\.id) + oldList.flatMap(\.channels) != newList.map(\.id) + newList.flatMap(\.channels) {
            changes.append(.note("Reordered categories and channels"))
        }
        return changes
    }

    private func systemMessageChanges(old: [String: JSONValue], new: [String: JSONValue]) -> [AuditLogChange] {
        let labels = [
            ("user_joined", "Join messages"),
            ("user_left", "Leave messages"),
            ("user_kicked", "Kick messages"),
            ("user_banned", "Ban messages")
        ]
        return labels.compactMap { key, label in
            let before = old[key]?.string
            let after = new[key]?.string
            guard before != after else { return nil }
            return .value(field: label, old: before.map(channelName) ?? "Off", new: after.map(channelName) ?? "Off")
        }
    }

    private func reorderChanges(before: [JSONValue], after: [JSONValue]) -> [AuditLogChange] {
        let oldOrder = before.compactMap(\.string)
        let newOrder = after.compactMap(\.string)
        return newOrder.enumerated().compactMap { index, roleId in
            guard let oldIndex = oldOrder.firstIndex(of: roleId), oldIndex != index else { return nil }
            return .value(field: roleName(roleId), old: "#\(oldIndex + 1)", new: "#\(index + 1)")
        }
    }

    // MARK: - Permissions

    private func channelOverrideChanges(_ action: AuditLogAction, previous: AuditLogAction?) -> [AuditLogChange] {
        guard let new = Self.override(action.permissions) else { return [] }
        if let old = Self.override(previous?.permissions) {
            return overrideChanges(scope: nil, old: old, new: new)
        }
        // Stoat doesn't record the previous override, so list what's set now.
        let states = Permission.named.compactMap { entry -> AuditLogChange? in
            let state = Self.state(entry.permission, allow: new.allow, deny: new.deny)
            guard state != .neutral else { return nil }
            return .permission(scope: nil, name: entry.title, old: nil, new: state)
        }
        return states.isEmpty ? [.note("Cleared all permission overrides")] : states
    }

    private func overrideChanges(scope: String?, old: (allow: Int64, deny: Int64)?, new: (allow: Int64, deny: Int64)) -> [AuditLogChange] {
        let old = old ?? (0, 0)
        return Permission.named.compactMap { entry in
            let before = Self.state(entry.permission, allow: old.allow, deny: old.deny)
            let after = Self.state(entry.permission, allow: new.allow, deny: new.deny)
            guard before != after else { return nil }
            return .permission(scope: scope, name: entry.title, old: before, new: after)
        }
    }

    private func bitfieldChanges(scope: String?, old: Int64, new: Int64) -> [AuditLogChange] {
        let before = Permission(rawValue: old)
        let after = Permission(rawValue: new)
        return Permission.named.compactMap { entry in
            let wasOn = before.contains(entry.permission)
            let isOn = after.contains(entry.permission)
            guard wasOn != isOn else { return nil }
            return .permission(scope: scope, name: entry.title, old: wasOn ? .on : .off, new: isOn ? .on : .off)
        }
    }

    private static func state(_ permission: Permission, allow: Int64, deny: Int64) -> AuditLogChange.PermissionState {
        if Permission(rawValue: deny).contains(permission) { return .denied }
        if Permission(rawValue: allow).contains(permission) { return .allowed }
        return .neutral
    }

    /// Reads an override stored as `{a, d}` (roles, channels) or `{allow, deny}` (channel role edits).
    private static func override(_ value: JSONValue?) -> (allow: Int64, deny: Int64)? {
        guard let value, value.object != nil else { return nil }
        let allow = value["a"]?.int ?? value["allow"]?.int ?? 0
        let deny = value["d"]?.int ?? value["deny"]?.int ?? 0
        return (allow, deny)
    }

    // MARK: - Formatting

    private func yesNo(_ value: JSONValue?) -> String? {
        value?.bool.map { $0 ? "Yes" : "No" }
    }

    private func onOff(_ value: JSONValue?) -> String? {
        value?.bool.map { $0 ? "On" : "Off" }
    }

    private static func formatDate(_ raw: String) -> String {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = withFraction.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func summary(_ value: JSONValue) -> String {
        switch value {
        case .null: "none"
        case .bool(let bool): bool ? "Yes" : "No"
        case .int(let int): "\(int)"
        case .double(let double): "\(double)"
        case .string(let string): string
        case .array(let array): "\(array.count) items"
        case .object: "updated"
        }
    }
}
