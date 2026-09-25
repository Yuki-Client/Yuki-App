import XCTest
@testable import StoatCore
@testable import StoatState

@MainActor
final class StoreTests: XCTestCase {
    private func message(_ id: String, channel: String = "c", author: String = "a", nonce: String? = nil) -> Message {
        Message(id: id, nonce: nonce, channel: channel, author: author, content: id)
    }

    // MARK: Timeline

    func testTimelineKeepsMessagesSortedAndDeduplicated() {
        let timeline = ChannelTimeline(channelId: "c")
        XCTAssertTrue(timeline.upsert(message("01B")))
        XCTAssertTrue(timeline.upsert(message("01A")))
        XCTAssertTrue(timeline.upsert(message("01C")))
        XCTAssertFalse(timeline.upsert(message("01B")))
        XCTAssertEqual(timeline.messages.map(\.id), ["01A", "01B", "01C"])

        timeline.merge([message("01D"), message("00Z"), message("01A")])
        XCTAssertEqual(timeline.messages.map(\.id), ["00Z", "01A", "01B", "01C", "01D"])
    }

    func testConfirmedMessageReplacesPendingByNonce() {
        let timeline = ChannelTimeline(channelId: "c")
        timeline.pending = [PendingMessage(nonce: "N1", channelId: "c", content: "hi", attachments: [], replies: [], state: .sending, createdAt: Date())]
        timeline.upsert(message("01A", nonce: "N1"))
        XCTAssertTrue(timeline.pending.isEmpty)
        XCTAssertEqual(timeline.messages.count, 1)
    }

    func testTimelineUpdateAndTrim() {
        let timeline = ChannelTimeline(channelId: "c")
        timeline.merge((0..<10).map { message("01\($0)") })
        timeline.update(id: "015") { $0.pinned = true }
        XCTAssertEqual(timeline.message(id: "015")?.pinned, true)
        timeline.hasMoreBefore = false
        timeline.trim(keepingLast: 3)
        XCTAssertEqual(timeline.messages.map(\.id), ["017", "018", "019"])
        XCTAssertTrue(timeline.hasMoreBefore)
    }

    // MARK: Permissions

    private func serverStore(defaultPermissions: Int64, roles: [String: Role], memberRoles: [String], owner: String = "owner") -> NormalizedStore {
        let store = NormalizedStore()
        store.currentUserId = "me"
        store.users["me"] = User(id: "me", username: "me", relationship: .user)
        store.servers["s"] = Server(id: "s", owner: owner, name: "S", channels: ["c"], roles: roles, defaultPermissions: defaultPermissions)
        store.members["s"] = ["me": ServerMember(key: ServerMemberId(server: "s", user: "me"), roles: memberRoles)]
        return store
    }

    func testServerPermissionsApplyRolesInRankOrder() {
        let roles = [
            "low": Role(name: "Low", permissions: RolePermissions(a: Permission.manageMessages.rawValue, d: 0), rank: 10),
            "high": Role(name: "High", permissions: RolePermissions(a: 0, d: Permission.manageMessages.rawValue), rank: 1)
        ]
        let store = serverStore(defaultPermissions: Permission.default.rawValue, roles: roles, memberRoles: ["low", "high"])
        let permissions = store.permissions(in: store.servers["s"]!)
        XCTAssertTrue(permissions.contains(.sendMessage))
        // The higher-ranked role (lower number) is applied last, so its deny wins.
        XCTAssertFalse(permissions.contains(.manageMessages))
    }

    func testChannelOverridesAndOwner() {
        let roles = ["mod": Role(name: "Mod", rank: 0)]
        let store = serverStore(defaultPermissions: Permission.default.rawValue, roles: roles, memberRoles: ["mod"])
        var channel = Channel(id: "c", channelType: .textChannel, server: "s", name: "announcements")
        channel.defaultPermissions = RolePermissions(a: 0, d: Permission.sendMessage.rawValue)
        store.channels["c"] = channel
        XCTAssertFalse(store.hasPermission(.sendMessage, in: channel))

        channel.rolePermissions = ["mod": RolePermissions(a: Permission.sendMessage.rawValue, d: 0)]
        store.channels["c"] = channel
        XCTAssertTrue(store.hasPermission(.sendMessage, in: channel))

        let owned = serverStore(defaultPermissions: 0, roles: [:], memberRoles: [], owner: "me")
        XCTAssertTrue(owned.hasPermission(.manageServer, in: owned.servers["s"]!))
    }

    func testTimeoutLimitsPermissions() {
        let store = serverStore(defaultPermissions: Permission.default.rawValue, roles: [:], memberRoles: [])
        store.members["s"]?["me"]?.timeout = StoatDate.string(from: Date().addingTimeInterval(600))
        let channel = Channel(id: "c", channelType: .textChannel, server: "s", name: "general")
        store.channels["c"] = channel
        XCTAssertTrue(store.hasPermission(.viewChannel, in: channel))
        XCTAssertFalse(store.hasPermission(.sendMessage, in: channel))
    }

    func testExternalEmojisNeedPermissionInServerChannels() {
        let local = "01H0000000000000000000000A"
        let external = "01H0000000000000000000000B"
        let store = serverStore(defaultPermissions: Permission.default.rawValue, roles: [:], memberRoles: [])
        store.servers["other"] = Server(id: "other", owner: "owner", name: "Other", channels: [], roles: [:], defaultPermissions: 0)
        store.emojis[local] = Emoji(id: local, parent: .server(id: "s"), name: "local")
        store.emojis[external] = Emoji(id: external, parent: .server(id: "other"), name: "external")
        let channel = Channel(id: "c", channelType: .textChannel, server: "s", name: "general")
        store.channels["c"] = channel

        XCTAssertTrue(store.canUseEmoji(local, in: channel))
        XCTAssertFalse(store.canUseEmoji(external, in: channel))
        XCTAssertTrue(store.canUseEmoji("🎉", in: channel))
        XCTAssertEqual(store.emojiSections(for: channel).map(\.id), ["s"])

        store.servers["s"]?.defaultPermissions = Permission.default.union(.useExternalEmojis).rawValue
        XCTAssertTrue(store.canUseEmoji(external, in: channel))
        XCTAssertEqual(Set(store.emojiSections(for: channel).map(\.id)), ["s", "other"])

        let dm = Channel(id: "dm", channelType: .directMessage)
        XCTAssertTrue(store.canUseEmoji(external, in: dm))
    }

    func testSpoilerMarkingRenamesAttachment() {
        let attachment = OutgoingAttachment(data: Data(), filename: "cat.jpg", contentType: "image/jpeg", kind: .image)
        let spoiler = attachment.markedAsSpoiler(true)
        XCTAssertEqual(spoiler.filename, "SPOILER_cat.jpg")
        XCTAssertEqual(spoiler.id, attachment.id)
        XCTAssertTrue(spoiler.isSpoiler)
        XCTAssertEqual(spoiler.markedAsSpoiler(true).filename, "SPOILER_cat.jpg")
        XCTAssertEqual(spoiler.markedAsSpoiler(false).filename, "cat.jpg")
    }

    func testCanModerateRespectsRanking() {
        let roles = ["admin": Role(name: "Admin", rank: 1), "member": Role(name: "Member", rank: 5)]
        let store = serverStore(defaultPermissions: 0, roles: roles, memberRoles: ["admin"])
        store.members["s"]?["other"] = ServerMember(key: ServerMemberId(server: "s", user: "other"), roles: ["member"])
        store.members["s"]?["peer"] = ServerMember(key: ServerMemberId(server: "s", user: "peer"), roles: ["admin"])
        XCTAssertTrue(store.canModerate(userId: "other", in: "s"))
        XCTAssertFalse(store.canModerate(userId: "peer", in: "s"))
        XCTAssertFalse(store.canModerate(userId: "owner", in: "s"))
    }

    // MARK: Unreads

    func testUnreadAndMentions() {
        let store = NormalizedStore()
        store.unreadsLoaded = true
        store.currentUserId = "me"
        store.channels["c"] = Channel(id: "c", channelType: .directMessage, lastMessageId: "01B", recipients: ["me", "you"])
        store.unreads["c"] = ChannelUnread(channel: "c", user: "me", lastId: "01A")
        XCTAssertTrue(store.isUnread(channel: store.channels["c"]!))

        store.markRead(channelId: "c", messageId: "01B")
        XCTAssertFalse(store.isUnread(channel: store.channels["c"]!))

        // A mention for a message that was already read is one of Stoat's ghosts and is ignored.
        store.unreads["c"]?.mentions = ["01B"]
        XCTAssertEqual(store.mentionCount(channelId: "c"), 0)

        store.channels["c"]?.lastMessageId = "01C"
        store.unreads["c"]?.mentions = ["01C"]
        XCTAssertEqual(store.mentionCount(channelId: "c"), 1)
        XCTAssertEqual(store.badgeCount, 1)

        store.notificationOptions.channelMutes["c"] = NotificationOptions.MuteState()
        XCTAssertFalse(store.isUnread(channel: store.channels["c"]!))
    }

    func testNotificationOptionsMigratesLegacyMutes() throws {
        let options = try JSONDecoder().decode(NotificationOptions.self, from: Data(#"{"server":{"s1":"muted","s2":"all"},"channel":{},"channel_mutes":{"c1":{"until":1}}}"#.utf8))
        XCTAssertTrue(options.isServerMuted("s1"))
        XCTAssertEqual(options.server["s2"], .all)
        XCTAssertFalse(options.isChannelMuted("c1"), "Expired mutes should not apply")
    }

    // MARK: Ordering & formatting

    func testDirectChannelsSortByActivityWithSavedNotesFirst() {
        let store = NormalizedStore()
        store.currentUserId = "me"
        store.channels["old"] = Channel(id: "old", channelType: .directMessage, lastMessageId: "01A", recipients: ["me", "x"], active: true)
        store.channels["new"] = Channel(id: "new", channelType: .group, name: "G", lastMessageId: "01Z", recipients: ["me", "y"])
        store.channels["closed"] = Channel(id: "closed", channelType: .directMessage, lastMessageId: "01Y", recipients: ["me", "z"], active: false)
        store.channels["saved"] = Channel(id: "saved", channelType: .savedMessages, user: "me")
        XCTAssertEqual(store.directChannels.map(\.id), ["saved", "new", "old"])
    }

    func testMentionFormatter() {
        let store = NormalizedStore()
        store.users["01H00000000000000000000000"] = User(id: "01H00000000000000000000000", username: "alice", displayName: "Alice")
        store.channels["01H11111111111111111111111"] = Channel(id: "01H11111111111111111111111", channelType: .textChannel, server: "s", name: "general")
        let text = MentionFormatter.plainText("hi <@01H00000000000000000000000> see <#01H11111111111111111111111>", store: store)
        XCTAssertEqual(text, "hi @Alice see #general")
    }

    func testInviteCodeParsing() {
        XCTAssertEqual(AppStore.inviteCode(from: "https://stoat.chat/invite/Testers"), "Testers")
        XCTAssertEqual(AppStore.inviteCode(from: "rvlt.gg/abc123"), "abc123")
        XCTAssertEqual(AppStore.inviteCode(from: "  abc123 "), "abc123")
    }

    func testNonceShape() {
        let nonce = AppStore.makeNonce()
        XCTAssertEqual(nonce.count, 26)
        XCTAssertNotEqual(nonce, AppStore.makeNonce())
    }
    // MARK: Roles, permissions and categories

    func testPermissionOverrideStatesKeepOtherBits() {
        let unknownBit: Int64 = 1 << 50
        var value = PermissionOverrideValue(allow: Permission.sendMessage.rawValue | unknownBit, deny: Permission.react.rawValue)
        XCTAssertEqual(value.state(of: .sendMessage), .allow)
        XCTAssertEqual(value.state(of: .react), .deny)
        XCTAssertEqual(value.state(of: .viewChannel), .neutral)

        value.set(.sendMessage, to: .deny)
        value.set(.react, to: .neutral)
        value.set(.viewChannel, to: .allow)
        XCTAssertEqual(value.allow, Permission.viewChannel.rawValue | unknownBit)
        XCTAssertEqual(value.deny, Permission.sendMessage.rawValue)
        XCTAssertEqual(value.allowedCount, 2)
        XCTAssertEqual(value.deniedCount, 1)
        XCTAssertEqual(PermissionOverrideValue(RolePermissions(a: 4, d: 8)), PermissionOverrideValue(allow: 4, deny: 8))
    }

    func testReorderMatchesSwiftUIMoveSemantics() {
        let items = ["a", "b", "c", "d"]
        XCTAssertEqual(AppStore.reorder(items, from: [0], to: 3), ["b", "c", "a", "d"])
        XCTAssertEqual(AppStore.reorder(items, from: [3], to: 0), ["d", "a", "b", "c"])
        XCTAssertEqual(AppStore.reorder(items, from: [1, 2], to: 4), ["a", "d", "b", "c"])
        XCTAssertEqual(AppStore.reorder(items, from: [2], to: 2), items)
    }

    func testRoleOrderMustKeepLockedRolesInPlace() {
        let current = ["admin", "mod", "member", "guest"]
        let locked: Set<String> = ["admin", "mod"]
        XCTAssertTrue(AppStore.isValidRoleOrder(current: current, proposed: ["admin", "mod", "guest", "member"], locked: locked))
        XCTAssertFalse(AppStore.isValidRoleOrder(current: current, proposed: ["admin", "guest", "mod", "member"], locked: locked))
        XCTAssertFalse(AppStore.isValidRoleOrder(current: current, proposed: ["admin", "mod", "member"], locked: locked))
    }

    func testRoleRankingAllowsOwnerAndLowerRolesOnly() {
        let store = NormalizedStore()
        store.currentUserId = "me"
        store.users["me"] = User(id: "me", username: "me")
        let roles = [
            "top": Role(name: "Top", permissions: RolePermissions(a: Permission.manageRole.rawValue), rank: 0),
            "mine": Role(name: "Mine", permissions: RolePermissions(a: Permission.manageRole.rawValue), rank: 1),
            "low": Role(name: "Low", rank: 2)
        ]
        store.servers["s"] = Server(id: "s", owner: "owner", name: "S", roles: roles)
        store.members["s"] = ["me": ServerMember(key: ServerMemberId(server: "s", user: "me"), roles: ["mine"])]

        XCTAssertEqual(store.rolesByRank(serverId: "s").map(\.id), ["top", "mine", "low"])
        XCTAssertFalse(store.canEditRole("top", serverId: "s"))
        XCTAssertFalse(store.canEditRole("mine", serverId: "s"))
        XCTAssertTrue(store.canEditRole("low", serverId: "s"))

        store.servers["s"]?.owner = "me"
        XCTAssertTrue(store.canEditRole("top", serverId: "s"))
    }

    func testCategoriesDropUnknownAndDuplicateChannels() {
        let categories = [
            ServerCategory(id: "1", title: "  Text  ", channels: ["a", "gone", "b"]),
            ServerCategory(id: "2", title: String(repeating: "x", count: 40), channels: ["b", "c"])
        ]
        let cleaned = AppStore.sanitizedCategories(categories, serverChannels: ["a", "b", "c"])
        XCTAssertEqual(cleaned[0].title, "Text")
        XCTAssertEqual(cleaned[0].channels, ["a", "b"])
        XCTAssertEqual(cleaned[1].channels, ["c"])
        XCTAssertEqual(cleaned[1].title.count, 32)
    }
    func testStoatLinkParsing() {
        let c = "01KSN15QZZNDFS2CRR77VAARJ1", m = "01M2KMNJBWB7J0SVEHS22J8ZXS", srv = "01H00000000000000000000000"
        XCTAssertEqual(StoatLink.parse(URL(string: "https://stoat.chat/server/\(srv)/channel/\(c)/\(m)")!, appHost: nil), .channel(c, messageId: m))
        XCTAssertEqual(StoatLink.parse(URL(string: "/server/\(srv)/channel/\(c)/\(m)")!, appHost: nil), .channel(c, messageId: m))
        XCTAssertEqual(StoatLink.parse(URL(string: "https://stoat.chat/channel/\(c)")!, appHost: nil), .channel(c, messageId: nil))
        XCTAssertEqual(StoatLink.parse(URL(string: "yuki://channel/\(c)/\(m)")!, appHost: nil), .channel(c, messageId: m))
        XCTAssertEqual(StoatLink.parse(URL(string: "https://stt.gg/8eq4K4fa")!, appHost: nil), .invite("8eq4K4fa"))
        XCTAssertEqual(StoatLink.parse(URL(string: "https://chat.example.com/invite/abc")!, appHost: "chat.example.com"), .invite("abc"))
        XCTAssertNil(StoatLink.parse(URL(string: "https://github.com/stoatchat/for-web/channel/\(c)")!, appHost: nil))
        XCTAssertEqual(StoatLink.parse(URL(string: "https://stoat.chat/discover")!, appHost: nil), .discover)
        XCTAssertEqual(StoatLink.parse(URL(string: "https://stt.gg/discover/servers?tag=gaming")!, appHost: nil), .discover)
        XCTAssertEqual(StoatLink.parse(URL(string: "yuki://discover")!, appHost: nil), .discover)
        XCTAssertEqual(StoatLink.parse(URL(string: "yuki://user/01H11111111111111111111111")!, appHost: nil), .user("01H11111111111111111111111"))
    }
    // MARK: Notification Centre

    func testNotificationKinds() {
        let store = NormalizedStore()
        store.currentUserId = "me"
        store.channels["t"] = Channel(id: "t", channelType: .textChannel, server: "s", name: "general")
        store.channels["d"] = Channel(id: "d", channelType: .directMessage, recipients: ["me", "you"])
        store.members["s"] = ["me": ServerMember(key: ServerMemberId(server: "s", user: "me"), roles: ["mods"])]

        XCTAssertEqual(store.notificationKind(for: Message(id: "01A", channel: "t", author: "you", content: "hi", mentions: ["me"])), .mention)
        XCTAssertEqual(store.notificationKind(for: Message(id: "01B", channel: "t", author: "you", content: "hi", roleMentions: ["mods"])), .roleMention)
        XCTAssertEqual(store.notificationKind(for: Message(id: "01C", channel: "t", author: "you", content: "hi", flags: 2)), .everyone)
        XCTAssertEqual(store.notificationKind(for: Message(id: "01D", channel: "d", author: "you", content: "hi")), .directMessage)
        XCTAssertNil(store.notificationKind(for: Message(id: "01E", channel: "t", author: "you", content: "hi")))
        XCTAssertNil(store.notificationKind(for: Message(id: "01F", channel: "t", author: "you", content: "hi", roleMentions: ["other"])))
        // Your own messages never count.
        XCTAssertNil(store.notificationKind(for: Message(id: "01G", channel: "d", author: "me", content: "hi")))
    }

    func testNotificationReadStateFollowsStoat() {
        let store = NormalizedStore()
        store.currentUserId = "me"
        let item = NotificationItem(message: Message(id: "01B", channel: "t", author: "you", mentions: ["me"]), kind: .mention)

        XCTAssertTrue(store.isUnread(item))
        store.unreads["t"] = ChannelUnread(channel: "t", user: "me")
        store.unreads["t"]?.lastId = "01C"
        XCTAssertFalse(store.isUnread(item))
        // Still read, even though Stoat kept listing the mention: that's how ghost mentions linger.
        store.unreads["t"]?.mentions = ["01B"]
        XCTAssertFalse(store.isUnread(item))
    }
    func testPreviewTextRemovesMarkdown() {
        let store = NormalizedStore()
        XCTAssertEqual(MentionFormatter.previewText("**Kuma dashboard login** is `ready`", store: store), "Kuma dashboard login is ready")
        XCTAssertEqual(MentionFormatter.previewText("hi :01H11111111111111111111111: yourmom_pl", store: store), "hi :01H11111111111111111111111: yourmom_pl")
    }
    func testQuickReactionsFavourFrequentAndRecentUse() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ReactionHistoryTests"))
        defaults.removePersistentDomain(forName: "ReactionHistoryTests")
        let history = ReactionHistory(defaults: defaults)
        let now = Date()
        let custom = "01H11111111111111111111111"

        // Nothing used yet: the defaults.
        XCTAssertEqual(history.quickReactions(at: now), ReactionHistory.defaultReactions)

        for _ in 0..<3 { history.record(custom, at: now) }
        history.record("🥺", at: now)
        // Used often, but two months ago, so it counts for less than recent use.
        for _ in 0..<5 { history.record("🎉", at: now.addingTimeInterval(-60 * 24 * 60 * 60)) }
        defaults.set("🫠 👍", forKey: "yuki.recentEmoji")

        XCTAssertEqual(history.quickReactions(at: now), [custom, "🥺", "🎉", "🫠", "👍", "❤️"])
        // Custom emoji the user can't use any more are skipped.
        XCTAssertEqual(history.quickReactions(at: now, isAvailable: { $0 != custom }).first, "🥺")
    }
    // MARK: Navigation

    /// Builds a store with one server of two channels and a DM, ready to navigate.
    private func navigationStore() -> AppStore {
        let app = AppStore()
        let store = app.store
        store.currentUserId = "me"
        store.servers["s"] = Server(id: "s", owner: "me", name: "Server", channels: ["general", "random"])
        store.channels["general"] = Channel(id: "general", channelType: .textChannel, server: "s", name: "general")
        store.channels["random"] = Channel(id: "random", channelType: .textChannel, server: "s", name: "random")
        store.channels["voice"] = Channel(id: "voice", channelType: .voiceChannel, server: "s", name: "Voice")
        store.channels["dm"] = Channel(id: "dm", channelType: .directMessage, recipients: ["me", "you"])
        return app
    }

    func testOpeningAChannelAlwaysAsksToShowIt() {
        let app = navigationStore()
        app.selectServer("s")

        app.openChannel("general")
        XCTAssertEqual(app.selectedChannelId, "general")
        let afterFirst = app.channelOpenCount
        XCTAssertGreaterThan(afterFirst, 0)

        // Opening the channel you're already in must still ask to show it: on iPhone the chat
        // may not be on screen, and nothing else would navigate back to it.
        app.openChannel("general")
        XCTAssertGreaterThan(app.channelOpenCount, afterFirst)

        app.openChannel("random")
        XCTAssertEqual(app.selectedChannelId, "random")
    }

    func testOpeningAChannelClearsRepliesAndEditing() {
        let app = navigationStore()
        let draft = Message(id: "01A", channel: "general", author: "you", content: "hi")
        app.replyingTo = [AppStore.ReplyDraft(message: draft, mention: true)]
        app.editingMessage = draft

        app.openChannel("random")
        XCTAssertTrue(app.replyingTo.isEmpty)
        XCTAssertNil(app.editingMessage)
    }

    func testLastChannelPerServerAndDMs() {
        let app = navigationStore()
        app.selectServer("s")
        app.openChannel("general")
        app.selectServer(nil)
        app.openChannel("dm")

        XCTAssertEqual(app.lastChannel(forServer: "s"), "general")
        XCTAssertEqual(app.lastChannel(forServer: nil), "dm")

        // Back in the server, swiping opens the channel that was last read there.
        app.selectServer("s")
        XCTAssertTrue(app.openLastChannel())
        XCTAssertEqual(app.selectedChannelId, "general")
    }

    func testLastChannelForgetsChannelsThatWentAway() {
        let app = navigationStore()
        app.selectServer("s")
        app.openChannel("general")
        app.store.channels.removeValue(forKey: "general")

        XCTAssertNil(app.lastChannel(forServer: "s"))
        XCTAssertFalse(app.openLastChannel())
    }

    func testVoiceChannelsAreNotRememberedAsTheLastChannel() {
        let app = navigationStore()
        app.selectServer("s")
        app.openChannel("general")
        app.openChannel("voice")

        // Swiping back into a server should land in a chat, not a call.
        XCTAssertEqual(app.lastChannel(forServer: "s"), "general")
    }

    func testSelectingAServerKeepsTheChannelWhenItBelongsToIt() {
        let app = navigationStore()
        app.selectServer("s")
        app.openChannel("general")

        app.selectServer("s")
        XCTAssertEqual(app.selectedChannelId, "general")

        app.selectServer(nil)
        XCTAssertNil(app.selectedChannelId)
    }

    func testAskingForTheChannelList() {
        let app = navigationStore()
        let before = app.channelListRequestCount
        app.showChannelList()
        XCTAssertGreaterThan(app.channelListRequestCount, before)
    }

    func testOpeningAMessageQueuesTheJumpForItsChannel() {
        let app = navigationStore()
        app.openMessage("01M", in: "general")

        XCTAssertEqual(app.selectedChannelId, "general")
        XCTAssertNil(app.takePendingJump(for: "random"))
        XCTAssertEqual(app.takePendingJump(for: "general"), "01M")
        // Taken once only, so re-entering the channel doesn't jump again.
        XCTAssertNil(app.takePendingJump(for: "general"))
    }
    // MARK: Ghost mentions and unreads

    func testMentionsBehindWhatYouReadDontCount() {
        let store = NormalizedStore()
        store.unreadsLoaded = true
        store.currentUserId = "me"
        store.channels["c"] = Channel(id: "c", channelType: .textChannel, server: "s", name: "general", lastMessageId: "01C")
        var unread = ChannelUnread(channel: "c", user: "me")
        unread.lastId = "01C"
        // Stoat adds role and @everyone mentions after the fact, so one can arrive for a message
        // that was already read.
        unread.mentions = ["01B"]
        store.unreads["c"] = unread

        XCTAssertEqual(store.mentionCount(channelId: "c"), 0)
        XCTAssertFalse(store.isUnread(channel: store.channels["c"]!))
        XCTAssertEqual(store.channelsWithStaleMentions["c"], "01C")

        // A mention for something newer still counts.
        store.unreads["c"]?.mentions = ["01B", "01D"]
        XCTAssertEqual(store.mentionCount(channelId: "c"), 1)
        XCTAssertTrue(store.isUnread(channel: store.channels["c"]!))
        XCTAssertNil(store.channelsWithStaleMentions["c"])
    }

    func testNothingIsUnreadBeforeUnreadsLoad() {
        let store = NormalizedStore()
        store.channels["c"] = Channel(id: "c", channelType: .textChannel, server: "s", name: "general", lastMessageId: "01C")
        XCTAssertFalse(store.isUnread(channel: store.channels["c"]!))
        store.unreadsLoaded = true
        XCTAssertTrue(store.isUnread(channel: store.channels["c"]!))
    }

    func testChannelPointingAtAMessageThatIsGoneReadsAsRead() {
        let store = NormalizedStore()
        store.unreadsLoaded = true
        store.currentUserId = "me"
        // The channel claims a newer message than anything that exists, as Stoat leaves it after
        // a delete.
        store.channels["c"] = Channel(id: "c", channelType: .textChannel, server: "s", name: "general", lastMessageId: "01Z")
        var unread = ChannelUnread(channel: "c", user: "me")
        unread.lastId = "01C"
        store.unreads["c"] = unread

        // Without the messages, Yuki can't tell, so it stays unread.
        XCTAssertTrue(store.isUnread(channel: store.channels["c"]!))

        let timeline = store.timeline(for: "c")
        timeline.merge([Message(id: "01B", channel: "c", author: "you"), Message(id: "01C", channel: "c", author: "you")])
        timeline.isSynced = true
        XCTAssertFalse(store.isUnread(channel: store.channels["c"]!))

        // A genuinely newer message is still unread.
        timeline.merge([Message(id: "01D", channel: "c", author: "you")])
        XCTAssertTrue(store.isUnread(channel: store.channels["c"]!))
    }

    // MARK: Server folders

    private func servers(_ ids: String...) -> [String: Server] {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, Server(id: $0, owner: "me", name: $0, channels: [])) })
    }

    private func ids(_ entries: [SidebarEntry]) -> [String] {
        entries.map { entry in
            switch entry {
            case .server(let server): server.id
            case .folder(let folder, let servers): "\(folder.id)[\(servers.map(\.id).joined(separator: ","))]"
            }
        }
    }

    func testFoldersSitWhereStoatForWebPutsThem() {
        let known = servers("a", "b", "c", "d", "e")
        let folder = ServerFolder(id: "folder-1", name: "Games", servers: ["c", "a", "gone"])

        // Without its own place in the order, a folder goes where its first listed server is.
        var layout = ServerSidebarLayout(order: ["b", "c", "d", "a"], folders: [folder])
        XCTAssertEqual(ids(layout.entries(servers: known)), ["b", "folder-1[c,a]", "d", "e"])

        // With one, it goes there, and servers not in the order go at the end.
        layout.order = ["d", "folder-1", "c", "a", "b"]
        XCTAssertEqual(ids(layout.entries(servers: known)), ["d", "folder-1[c,a]", "b", "e"])

        // A folder with none of the user's servers isn't drawn.
        layout.folders = [ServerFolder(id: "folder-2", name: "Old", servers: ["gone"])]
        XCTAssertEqual(ids(layout.entries(servers: known)), ["d", "c", "a", "b", "e"])
    }

    func testFolderChangesKeepTheListInPlace() {
        let known = servers("a", "b", "c", "d")
        var layout = ServerSidebarLayout(order: ["a", "b", "c", "d"], folders: [])

        layout = layout.creatingFolder(id: "folder-1", name: "F", serverIds: ["b"], servers: known)
        XCTAssertEqual(ids(layout.entries(servers: known)), ["a", "folder-1[b]", "c", "d"])
        // Members follow the folder, so they keep their place if the folder goes.
        XCTAssertEqual(layout.order, ["a", "folder-1", "b", "c", "d"])

        // Dropping a server on the folder adds it without moving the folder.
        layout = layout.moving("a", onto: "folder-1", servers: known)!
        XCTAssertEqual(ids(layout.entries(servers: known)), ["folder-1[b,a]", "c", "d"])

        // Dropping one on a server inside the folder puts it there.
        layout = layout.moving("d", onto: "b", servers: known)!
        XCTAssertEqual(ids(layout.entries(servers: known)), ["folder-1[d,b,a]", "c"])

        // Taking one out puts it just below the folder.
        layout = layout.removingServerFromFolder("b", servers: known)
        XCTAssertEqual(ids(layout.entries(servers: known)), ["folder-1[d,a]", "b", "c"])

        // Folders move as one entry.
        layout = layout.moving("folder-1", onto: "c", servers: known)!
        XCTAssertEqual(ids(layout.entries(servers: known)), ["b", "c", "folder-1[d,a]"])

        // Dragging a server out onto a top-level server takes it out of the folder.
        layout = layout.moving("a", onto: "b", servers: known)!
        XCTAssertEqual(ids(layout.entries(servers: known)), ["a", "b", "c", "folder-1[d]"])

        // Removing the folder leaves its servers where it was, and an emptied folder is dropped.
        let unpacked = layout.deletingFolder("folder-1", servers: known)
        XCTAssertEqual(ids(unpacked.entries(servers: known)), ["a", "b", "c", "d"])
        XCTAssertTrue(unpacked.folders.isEmpty)
        let emptied = layout.removingServerFromFolder("d", servers: known)
        XCTAssertTrue(emptied.folders.isEmpty)
        XCTAssertFalse(emptied.order.contains("folder-1"))
    }

    func testReorderingInsideAFolder() {
        let known = servers("a", "b", "c")
        let layout = ServerSidebarLayout(order: [], folders: [ServerFolder(id: "folder-1", name: "F", servers: ["a", "gone", "b", "c"])])
        let moved = layout.movingInFolder("folder-1", from: IndexSet(integer: 2), to: 0, servers: known)
        XCTAssertEqual(moved.folders.first?.servers, ["c", "a", "b", "gone"])
        XCTAssertNil(layout.moving("a", onto: "folder-1", servers: known))
    }

    func testFolderSettingsReadWhatStoatForWebWrites() throws {
        let folders = try JSONDecoder().decode(ServerFoldersSetting.self, from: Data("""
        {"folders":[{"id":"folder-01J","name":"Games","colour":"#ff0000","collapsed":true,"servers":["a","b"]},
                    {"id":"folder-01K","servers":["b","c"]},{"name":"no id"}]}
        """.utf8))
        let cleaned = ServerFolder.cleaned(folders.folders)
        XCTAssertEqual(cleaned.map(\.id), ["folder-01J", "folder-01K"])
        XCTAssertEqual(cleaned[0].isCollapsed, true)
        // A server can only be in one folder.
        XCTAssertEqual(cleaned[1].servers, ["c"])

        let ordering = try JSONDecoder().decode(ServerOrderingSetting.self, from: Data("""
        {"servers":["a","b","a",4],"serverSidebar":["folder-01J","a",{"servers":["z"]}]}
        """.utf8))
        XCTAssertEqual(ordering.servers, ["a", "b"])
        XCTAssertEqual(ordering.serverSidebar, ["folder-01J", "a", "z"])
        XCTAssertNil(try JSONDecoder().decode(ServerOrderingSetting.self, from: Data(#"{"servers":["a"]}"#.utf8)).serverSidebar)

        // Written back, an open folder leaves out `collapsed` like Stoat for Web does.
        let written = String(decoding: try JSONEncoder().encode(ServerFoldersSetting(folders: [ServerFolder(id: "folder-1", name: "F", servers: ["a"])])), as: UTF8.self)
        XCTAssertFalse(written.contains("collapsed"))
        XCTAssertTrue(ServerFolder.newId().hasPrefix("folder-"))
        XCTAssertEqual(ServerFolder.newId().count, 7 + 26)
    }

    // MARK: Voice

    func testServerShowsACallWhenAnyChannelHasOne() {
        let store = NormalizedStore()
        store.servers["s"] = Server(id: "s", owner: "me", name: "S", channels: ["text", "voice"])
        XCTAssertFalse(store.hasActiveCall(serverId: "s"))
        store.voiceStates["voice"] = [:]
        XCTAssertFalse(store.hasActiveCall(serverId: "s"))
        store.voiceStates["voice"] = ["you": UserVoiceState(id: "you")]
        XCTAssertTrue(store.hasActiveCall(serverId: "s"))
    }

    // MARK: Deleted mentions

    func testDeletedMentionsStopCounting() {
        let app = AppStore()
        app.store.currentUserId = "me"
        app.store.channels["c"] = Channel(id: "c", channelType: .textChannel, server: "s", name: "general", lastMessageId: "01D")
        var unread = ChannelUnread(channel: "c", user: "me")
        unread.lastId = "01A"
        unread.mentions = ["01B", "01C"]
        app.store.unreads["c"] = unread

        app.forgetMentions(["01B", "01X"], in: "c")
        XCTAssertEqual(app.store.mentionCount(channelId: "c"), 1)
        // Only IDs that were mentions are remembered, for when Stoat lists them again.
        XCTAssertEqual(app.deletedMentionIds, ["01B"])
    }

    func testChannelsListedTwiceShowOnce() {
        let store = NormalizedStore()
        store.currentUserId = "me"
        var server = Server(id: "s", owner: "me", name: "S", channels: ["a", "b", "c"])
        server.categories = [
            ServerCategory(id: "one", title: "One", channels: ["a", "b", "a"]),
            ServerCategory(id: "two", title: "Two", channels: ["b", "c"])
        ]
        store.servers["s"] = server
        for id in ["a", "b", "c"] {
            store.channels[id] = Channel(id: id, channelType: .textChannel, server: "s", name: id)
        }
        let result = store.categorizedChannels(forServer: "s")
        XCTAssertEqual(result.categorized.map { $0.channels.map(\.id) }, [["a", "b"], ["c"]])
        XCTAssertTrue(result.uncategorized.isEmpty)
    }
}
