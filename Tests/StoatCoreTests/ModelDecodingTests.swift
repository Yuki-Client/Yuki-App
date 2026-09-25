import XCTest
@testable import StoatCore

/// Payload shapes follow the serde definitions in stoatchat/crates/core/models/src/v0
/// and stoatchat/crates/core/database/src/events/client.rs.
final class ModelDecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testDecodeUser() throws {
        let user = try decode(User.self, """
        {
            "_id": "01GABCDEF0123456789ABCDEFG",
            "username": "frosty",
            "discriminator": "1337",
            "display_name": "Yuki User",
            "relations": [{"_id": "01H0000000000000000000000A", "status": "Friend"}],
            "badges": 5,
            "status": {"text": "Coding", "presence": "Online"},
            "flags": 0,
            "privileged": true,
            "relationship": "User",
            "online": true
        }
        """)
        XCTAssertEqual(user.id, "01GABCDEF0123456789ABCDEFG")
        XCTAssertEqual(user.visibleName, "Yuki User")
        XCTAssertEqual(user.fullHandle, "frosty#1337")
        XCTAssertEqual(user.status?.presence, .online)
        XCTAssertEqual(user.relationship, .user)
        XCTAssertEqual(user.effectivePresence, .online)
        XCTAssertEqual(user.decodedBadges.map(\.id_name), ["staff", "developer", "supporter"])
    }

    func testUnknownRelationshipFallsBackToNone() throws {
        let user = try decode(User.self, #"{"_id":"01A","username":"x","discriminator":"0001","relationship":"SomethingNew"}"#)
        XCTAssertEqual(user.relationship, .none)
        XCTAssertEqual(user.effectivePresence, .invisible)
    }

    func testServerDefaultPermissionsIsANumber() throws {
        // Regression: the old model expected an array here, which broke every Ready payload.
        let server = try decode(Server.self, """
        {
            "_id": "01SERVER00000000000000000A",
            "owner": "01OWNER000000000000000000A",
            "name": "Kuma",
            "channels": ["c1", "c2", "c3"],
            "categories": [{"id": "cat1", "title": "Text", "channels": ["c1", "c2"]}],
            "roles": {
                "r_admin": {"name": "Admin", "permissions": {"a": 8, "d": 0}, "colour": "#FF0000", "hoist": true, "rank": 0},
                "r_member": {"name": "Member", "permissions": {"a": 0, "d": 4194304}, "rank": 10}
            },
            "default_permissions": 4287426563,
            "flags": 1
        }
        """)
        XCTAssertEqual(server.defaultPermissions, 4_287_426_563)
        XCTAssertEqual(server.categories?.first?.channels, ["c1", "c2"])
        XCTAssertEqual(server.roles["r_member"]?.permissions.d, 4_194_304)
        XCTAssertTrue(server.isVerified)
    }

    func testDecodeChannelVariants() throws {
        let dm = try decode(Channel.self, #"{"channel_type":"DirectMessage","_id":"01DM","active":true,"recipients":["me","them"],"last_message_id":"01MSG"}"#)
        XCTAssertEqual(dm.otherRecipient(currentUserId: "me"), "them")
        XCTAssertEqual(dm.displayName(withUsers: ["them": User(id: "them", username: "Them")], currentUserId: "me"), "Them")

        let text = try decode(Channel.self, """
        {"channel_type":"TextChannel","_id":"01TEXT","server":"01S","name":"general","default_permissions":{"a":0,"d":4194304},"role_permissions":{"r1":{"a":4194304,"d":0}},"nsfw":true,"voice":{"max_users":10}}
        """)
        XCTAssertEqual(text.defaultPermissions?.d, 4_194_304)
        XCTAssertEqual(text.rolePermissions["r1"]?.a, 4_194_304)
        XCTAssertTrue(text.nsfw)
        XCTAssertTrue(text.supportsVoice)

        let saved = try decode(Channel.self, #"{"channel_type":"SavedMessages","_id":"01SAVED","user":"me"}"#)
        XCTAssertEqual(saved.displayName(), "Saved Notes")
    }

    func testDecodeMessageWithSystemEmbedsAndReactions() throws {
        let message = try decode(Message.self, """
        {
            "_id": "01F7Z0JJ9V1234567890ABCDEF",
            "channel": "01CHANNEL0000000000000000A",
            "author": "00000000000000000000000000",
            "system": {"type": "user_joined", "id": "01USER"},
            "embeds": [
                {"type": "Website", "url": "https://example.com", "title": "Example", "image": {"url": "https://example.com/a.png", "width": 100, "height": 50, "size": "Large"}},
                {"type": "Image", "url": "https://example.com/b.png", "width": 20, "height": 20, "size": "Preview"},
                {"type": "Unsupported future embed"}
            ],
            "reactions": {"👍": ["a", "b"]},
            "interactions": {"reactions": ["👍"], "restrict_reactions": true},
            "flags": 3
        }
        """)
        XCTAssertEqual(message.system, .userJoined(id: "01USER"))
        XCTAssertEqual(message.embeds?.count, 3)
        XCTAssertEqual(message.embeds?.first?.image?.url, "https://example.com/a.png")
        XCTAssertEqual(message.reactions["👍"], ["a", "b"])
        XCTAssertEqual(message.interactions?.restrictReactions, true)
        XCTAssertTrue(message.suppressesNotifications)
        XCTAssertTrue(message.timestamp.timeIntervalSince1970 > 1_600_000_000)
    }

    func testAttachmentURLsUseInstanceCDN() throws {
        let file = try decode(Attachment.self, """
        {"_id":"FILEID","tag":"attachments","filename":"cat.png","metadata":{"type":"Image","width":640,"height":480},"content_type":"image/png","size":1234}
        """)
        XCTAssertEqual(file.downloadURL(autumnBaseURL: "https://cdn.example")?.absoluteString, "https://cdn.example/attachments/FILEID")
        XCTAssertEqual(file.originalURL(autumnBaseURL: "https://cdn.example")?.absoluteString, "https://cdn.example/attachments/FILEID/original")
        XCTAssertEqual(file.dimensions, CGSize(width: 640, height: 480))
    }

    func testReadyPayloadSkipsMalformedEntries() throws {
        let event = try decode(GatewayEvent.self, """
        {
            "type": "Ready",
            "users": [{"_id": "01USER1", "username": "Alice", "discriminator": "0001", "relationship": "User", "online": true}, {"broken": true}],
            "servers": [{"_id": "01SERVER1", "owner": "01USER1", "name": "Lounge", "channels": ["01CHAN1"], "default_permissions": 0}],
            "channels": [{"_id": "01CHAN1", "channel_type": "TextChannel", "name": "general", "server": "01SERVER1"}],
            "members": [{"_id": {"server": "01SERVER1", "user": "01USER1"}, "joined_at": "2026-01-01T00:00:00.000Z", "roles": []}],
            "emojis": [{"_id": "01EMOJI", "parent": {"type": "Server", "id": "01SERVER1"}, "creator_id": "01USER1", "name": "wave", "animated": false, "nsfw": false}],
            "voice_states": [{"id": "01CHAN1", "participants": [{"id": "01USER1", "joined_at": "2026-01-01T00:00:00Z", "is_receiving": true, "is_publishing": false, "screensharing": false, "camera": false}]}]
        }
        """)
        guard case .ready(let ready) = event else { return XCTFail("Expected Ready") }
        XCTAssertEqual(ready.users.count, 1)
        XCTAssertEqual(ready.servers.first?.name, "Lounge")
        XCTAssertEqual(ready.members.first?.key.user, "01USER1")
        XCTAssertEqual(ready.emojis.first?.parent.serverId, "01SERVER1")
        XCTAssertEqual(ready.voiceStates.first?.participants.first?.id, "01USER1")
    }

    func testMessageUpdateReadsNestedData() throws {
        let event = try decode(GatewayEvent.self, #"{"type":"MessageUpdate","id":"01M","channel":"01C","data":{"content":"edited","edited":"2026-09-16T00:00:00Z"},"clear":["Pinned"]}"#)
        guard case .messageUpdate(let id, let channel, let data, let clear) = event else { return XCTFail("Expected MessageUpdate") }
        XCTAssertEqual(id, "01M")
        XCTAssertEqual(channel, "01C")
        XCTAssertEqual(data.content, "edited")
        XCTAssertEqual(clear, ["Pinned"])
    }

    func testDecodesErrorAndReactionEvents() throws {
        guard case .error(let type) = try decode(GatewayEvent.self, #"{"type":"Error","data":{"type":"InvalidSession"}}"#) else {
            return XCTFail("Expected Error")
        }
        XCTAssertEqual(type, "InvalidSession")

        guard case .messageReact(let id, let channel, let user, let emoji) = try decode(GatewayEvent.self, #"{"type":"MessageReact","id":"m","channel_id":"c","user_id":"u","emoji_id":"🔥"}"#) else {
            return XCTFail("Expected MessageReact")
        }
        XCTAssertEqual([id, channel, user, emoji], ["m", "c", "u", "🔥"])
    }

    func testDiscoverDecoding() throws {
        let server = try decode(DiscoverServer.self, #"{"_id":"01S","name":"Lounge","description":"Hi","tags":["chill"],"members":3441,"activity":"high","flags":2,"featured_new":true}"#)
        XCTAssertEqual(server.members, 3441)
        XCTAssertEqual(server.activity, .high)
        XCTAssertTrue(server.isVerified)
        XCTAssertFalse(server.isOfficial)
        XCTAssertTrue(server.isNew)

        let bot = try decode(DiscoverBot.self, #"{"_id":"01B","username":"bolt","profile":{"content":"Bridges chats"},"tags":[],"servers":3346,"usage":"no"}"#)
        XCTAssertEqual(bot.description, "Bridges chats")
        XCTAssertEqual(bot.usage, DiscoverActivity.none)

        XCTAssertEqual(try decode(DiscoverRequest.self, #"{"type":"Server","id":"01S","status":"UnderReview"}"#).status, .underReview)
        XCTAssertEqual(try decode(DiscoverRequest.self, #"{"type":"Server","id":"01S","status":{"Denied":"Too small"}}"#).status, .denied(reason: "Too small"))
        XCTAssertEqual(try decode(DiscoverRequest.self, #"{"type":"Bot","id":"01B","status":{"Approved":null}}"#).status, .approved(reason: nil))
    }

    func testVoiceCallUpdateDecoding() throws {
        guard case .voiceCallUpdate(let initiator, let channel, let ended) = try decode(GatewayEvent.self, #"{"type":"VoiceCallUpdate","initiator_id":"u","channel_id":"c","started_at":"2026-09-18T01:00:00Z","ended":false}"#) else {
            return XCTFail("Expected VoiceCallUpdate")
        }
        XCTAssertEqual(initiator, "u")
        XCTAssertEqual(channel, "c")
        XCTAssertFalse(ended)

        guard case .voiceChannelJoin(_, let state) = try decode(GatewayEvent.self, #"{"type":"VoiceChannelJoin","id":"c","state":{"id":"u","joined_at":"2026-09-18T01:00:00Z","is_receiving":true,"is_publishing":false,"screensharing":false,"camera":false}}"#) else {
            return XCTFail("Expected VoiceChannelJoin")
        }
        XCTAssertEqual(state.joinedAt, "2026-09-18T01:00:00Z")
    }

    func testBulkAndUnknownEvents() throws {
        guard case .bulk(let events) = try decode(GatewayEvent.self, #"{"type":"Bulk","v":[{"type":"ChannelStartTyping","id":"c","user":"u"},{"type":"SomethingNew"}]}"#) else {
            return XCTFail("Expected Bulk")
        }
        XCTAssertEqual(events.count, 2)
        if case .unknown(let type) = events[1] {
            XCTAssertEqual(type, "SomethingNew")
        } else {
            XCTFail("Expected unknown event")
        }
    }

    func testMessagesPageAcceptsBothResponseShapes() throws {
        let bare = try decode(DeltaAPIClient.MessagesPage.self, #"[{"_id":"01M","channel":"c","author":"a","content":"hi"}]"#)
        XCTAssertEqual(bare.messages.count, 1)

        let withUsers = try decode(DeltaAPIClient.MessagesPage.self, #"{"messages":[{"_id":"01M","channel":"c","author":"a"}],"users":[{"_id":"a","username":"alice","discriminator":"0001"}],"members":[]}"#)
        XCTAssertEqual(withUsers.users.first?.username, "alice")
    }

    func testLoginResponses() throws {
        guard case .mfa(let requirement) = try decode(LoginResponse.self, #"{"result":"MFA","ticket":"T","allowed_methods":["Totp","Recovery"]}"#) else {
            return XCTFail("Expected MFA")
        }
        XCTAssertEqual(requirement.allowedMethods, [.totp, .recovery])

        guard case .success(let session) = try decode(LoginResponse.self, #"{"result":"Success","_id":"S","user_id":"U","token":"TOKEN","name":"Yuki for iOS"}"#) else {
            return XCTFail("Expected Success")
        }
        XCTAssertEqual(session.token, "TOKEN")
    }

    func testMFALoginRequestEncoding() throws {
        let data = try JSONEncoder().encode(MFALoginRequest(ticket: "T", response: .totp("123456")))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["mfa_ticket"] as? String, "T")
        XCTAssertEqual((object?["mfa_response"] as? [String: String])?["totp_code"], "123456")
    }

    func testCustomEmojiIdDetection() {
        XCTAssertTrue(Emoji.isCustomEmojiId("01HZZZZZZZZZZZZZZZZZZZZZZZ"))
        XCTAssertFalse(Emoji.isCustomEmojiId("👍"))
        XCTAssertFalse(Emoji.isCustomEmojiId("thumbsup"))
    }

    func testSyncedSettingDecoding() throws {
        let settings = try decode([String: SyncedSetting].self, #"{"ordering":[1700000000000,"{\"servers\":[\"a\",\"b\"]}"]}"#)
        XCTAssertEqual(settings["ordering"]?.updatedAt, 1_700_000_000_000)
        XCTAssertTrue(settings["ordering"]?.value.contains("servers") == true)
    }
    func testRoleResponsesAndPermissionPayloads() throws {
        let created = try decode(DeltaAPIClient.NewRoleResponse.self, #"{"id":"R1","role":{"name":"Mods","permissions":{"a":0,"d":0},"rank":3}}"#)
        XCTAssertEqual(created.id, "R1")
        XCTAssertEqual(created.role.rank, 3)
        XCTAssertFalse(created.role.hoist)

        let payload = DeltaAPIClient.EditRolePayload(colour: nil, hoist: true, remove: ["Colour"])
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        XCTAssertNil(object?["name"])
        XCTAssertEqual(object?["hoist"] as? Bool, true)
        XCTAssertEqual(object?["remove"] as? [String], ["Colour"])

        let voice = Permission.speak.rawValue
        let override = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DeltaAPIClient.PermissionOverridePayload(allow: voice, deny: 0))) as? [String: Any]
        XCTAssertEqual((override?["allow"] as? NSNumber)?.int64Value, voice)
    }
    func testMultiFactorStatusAndAccount() throws {
        let none = try decode(MultiFactorStatus.self, #"{"email_otp":false,"trusted_handover":false,"email_mfa":false,"totp_mfa":false,"security_key_mfa":false,"recovery_active":false}"#)
        XCTAssertEqual(none.availableMethods, [.password])

        let totp = try decode(MultiFactorStatus.self, #"{"totp_mfa":true,"recovery_active":true}"#)
        XCTAssertEqual(totp.availableMethods, [.totp, .recovery])
        XCTAssertEqual(try decode(MultiFactorStatus.self, #"{"totp_mfa":true}"#).availableMethods, [.totp])

        let account = try decode(AccountInfo.self, #"{"_id":"01ACC","email":"a@example.com"}"#)
        XCTAssertEqual(account.email, "a@example.com")
    }
    func testBotResponses() throws {
        let created = try decode(BotWithUser.self, #"{"_id":"01BOT","owner":"01ME","token":"secret","public":true,"user":{"_id":"01BOT","username":"kuma","discriminator":"0001","bot":{"owner":"01ME"}}}"#)
        XCTAssertEqual(created.bot.id, "01BOT")
        XCTAssertTrue(created.bot.isPublic)
        XCTAssertFalse(created.bot.analytics)
        XCTAssertEqual(created.user.bot?.owner, "01ME")

        let owned = try decode(OwnedBotsResponse.self, #"{"bots":[{"_id":"01BOT","owner":"01ME","token":"t","public":false,"flags":1}],"users":[]}"#)
        XCTAssertTrue(owned.bots[0].isVerified)

        let publicBot = try decode(PublicBot.self, #"{"_id":"01BOT","username":"kuma"}"#)
        XCTAssertNil(publicBot.avatar)
    }
    func testSlowmodeEventAndWebhookDecoding() throws {
        guard case .userSlowmodes(let slowmodes) = try decode(GatewayEvent.self, #"{"type":"UserSlowmodes","slowmodes":[{"channel_id":"C1","duration":30,"retry_after":12}]}"#) else {
            return XCTFail("Expected UserSlowmodes")
        }
        XCTAssertEqual(slowmodes.first?.retryAfter, 12)

        let webhook = try decode(Webhook.self, #"{"id":"W1","name":"GitHub","creator_id":"U1","channel_id":"C1","permissions":0,"token":"abc"}"#)
        XCTAssertEqual(webhook.executeURL?.hasSuffix("/webhooks/W1/abc"), true)
        XCTAssertNil(try decode(Webhook.self, #"{"id":"W1","name":"n","creator_id":"U1","channel_id":"C1","permissions":0}"#).executeURL)
    }
    func testAuditLogDecoding() throws {
        let page = try decode(AuditLogPage.self, #"{"audit_logs":[{"_id":"01A","server":"S","user":"U","reason":"spam","action":{"type":"MemberEdit","user":"T","before":{"nickname":"a"},"after":{"nickname":"b","roles":["R"]}}},{"_id":"01B","server":"S","user":"U","action":{"type":"MessageBulkDelete","channel":"C","count":12}}],"users":[],"members":[]}"#)
        XCTAssertEqual(page.auditLogs.count, 2)
        XCTAssertEqual(page.auditLogs[0].action.after?["nickname"]?.string, "b")
        XCTAssertEqual(page.auditLogs[0].reason, "spam")
        XCTAssertEqual(page.auditLogs[1].action.count, 12)
    }
    func testBadgesComeFromStoat() throws {
        let developer = try decode(User.self, #"{"_id":"01K03S7V1R68Z9SGC1FVAN3WQ3","username":"Aki","discriminator":"8095","badges":1}"#)
        XCTAssertEqual(developer.decodedBadges.map(\.name), ["Stoat Developer"])

        let someone = try decode(User.self, #"{"_id":"01OTHER","username":"someone","discriminator":"0001"}"#)
        XCTAssertTrue(someone.decodedBadges.isEmpty)
    }
    private func auditEntry(_ id: String, _ action: String) throws -> AuditLogEntry {
        try decode(AuditLogEntry.self, #"{"_id":"\#(id)","server":"S","user":"U","action":\#(action)}"#)
    }

    private let auditNames = AuditLogChangeBuilder(
        userName: { "user:\($0)" },
        roleName: { "role:\($0)" },
        channelName: { "#\($0)" }
    )

    func testAuditLogMemberChanges() throws {
        let entry = try auditEntry("01B", #"{"type":"MemberEdit","user":"T","before":{"nickname":"old","roles":["R1","R2"]},"after":{"nickname":"new","roles":["R2","R3"],"timeout":"2026-09-20T10:00:00Z"}}"#)
        let changes = auditNames.changes(for: entry)
        XCTAssertEqual(changes.first, .value(field: "Nickname", old: "old", new: "new"))
        XCTAssertTrue(changes.contains(.added(field: "Roles", item: "role:R3")))
        XCTAssertTrue(changes.contains(.removed(field: "Roles", item: "role:R1")))
        XCTAssertTrue(changes.contains { if case .value("Timed out until", nil, _?) = $0 { true } else { false } })
    }

    func testAuditLogRemovedFieldAndSlowmode() throws {
        let entry = try auditEntry("01B", #"{"type":"ChannelEdit","channel":"C","before":{"description":"Old topic","slowmode":0},"after":{"slowmode":30}}"#)
        XCTAssertEqual(auditNames.changes(for: entry), [
            .value(field: "Topic", old: "Old topic", new: nil),
            .value(field: "Slowmode", old: "Off", new: "30 seconds")
        ])
    }

    func testAuditLogRoleAndServerPermissions() throws {
        // Role overrides use {a, d}: Kick Members (1<<6) allowed, Send Messages (1<<22) denied.
        let role = try auditEntry("01B", #"{"type":"RoleEdit","role":"R","before":{"permissions":{"a":64,"d":0}},"after":{"permissions":{"a":0,"d":4194304}}}"#)
        XCTAssertEqual(auditNames.changes(for: role), [
            .permission(scope: nil, name: "Kick Members", old: .allowed, new: .neutral),
            .permission(scope: nil, name: "Send Messages", old: .neutral, new: .denied)
        ])

        let server = try auditEntry("01C", #"{"type":"ServerEdit","before":{"default_permissions":4194304},"after":{"default_permissions":536870912}}"#)
        XCTAssertEqual(auditNames.changes(for: server), [
            .permission(scope: "Everyone", name: "Send Messages", old: .on, new: .off),
            .permission(scope: "Everyone", name: "React", old: .off, new: .on)
        ])
    }

    func testAuditLogChannelOverrideUsesPreviousEntry() throws {
        let older = try auditEntry("01A", #"{"type":"ChannelRolePermissionsEdit","channel":"C","role":"R","permissions":{"allow":4194304,"deny":0}}"#)
        let newer = try auditEntry("01B", #"{"type":"ChannelRolePermissionsEdit","channel":"C","role":"R","permissions":{"allow":0,"deny":4194304}}"#)
        XCTAssertTrue(AuditLogChangeBuilder.isPreviousOverride(older, of: newer))
        XCTAssertFalse(AuditLogChangeBuilder.isPreviousOverride(newer, of: older))

        XCTAssertEqual(auditNames.changes(for: newer, previous: older), [
            .permission(scope: nil, name: "Send Messages", old: .allowed, new: .denied)
        ])
        XCTAssertEqual(auditNames.changes(for: newer), [
            .permission(scope: nil, name: "Send Messages", old: nil, new: .denied)
        ])
    }

    func testAuditLogRolesReorder() throws {
        let entry = try auditEntry("01B", #"{"type":"RolesReorder","before":["A","B","C"],"after":["B","A","C"]}"#)
        XCTAssertEqual(auditNames.changes(for: entry), [
            .value(field: "role:B", old: "#2", new: "#1"),
            .value(field: "role:A", old: "#1", new: "#2")
        ])
    }
    func testAuditLogCategoryMove() throws {
        let entry = try auditEntry("01B", #"{"type":"ServerEdit","before":{"categories":[{"id":"K1","title":"Default","channels":["C1","C2"]},{"id":"K2","title":"Staff","channels":["C4"]}]},"after":{"categories":[{"id":"K1","title":"Default","channels":["C2"]},{"id":"K2","title":"Staff Stuff","channels":["C1","C4","C3"]}]}}"#)
        XCTAssertEqual(auditNames.changes(for: entry), [
            .value(field: "Category name", old: "Staff", new: "Staff Stuff"),
            .value(field: "#C1", old: "Default", new: "Staff Stuff"),
            .added(field: "Channels in Staff Stuff", item: "#C3")
        ])
    }
    func testCSSPaintSolidColours() {
        XCTAssertEqual(CSSPaint(css: "#ff0000"), .solid(.init(red: 1, green: 0, blue: 0)))
        XCTAssertEqual(CSSPaint(css: "#0f0"), .solid(.init(red: 0, green: 1, blue: 0)))
        XCTAssertEqual(CSSPaint(css: "rgba(0, 0, 255, 0.5)"), .solid(.init(red: 0, green: 0, blue: 1, alpha: 0.5)))
        XCTAssertEqual(CSSPaint(css: "Hot Pink")?.primaryColor, CSSPaint(css: "hotpink")?.primaryColor)
        XCTAssertNil(CSSPaint(css: "not a colour"))
        XCTAssertNil(CSSPaint(css: ""))
    }

    func testCSSPaintGradients() {
        guard case .linear(let angle, let stops) = CSSPaint(css: "linear-gradient(90deg, #ff0000, #0000ff)") else {
            return XCTFail("Expected a linear gradient")
        }
        XCTAssertEqual(angle, 90)
        XCTAssertEqual(stops.map(\.color), [.init(red: 1, green: 0, blue: 0), .init(red: 0, green: 0, blue: 1)])

        guard case .linear(let direction, let three) = CSSPaint(css: "linear-gradient(to bottom right, red, rgb(0, 128, 0) 30%, #00f)") else {
            return XCTFail("Expected a linear gradient with a direction")
        }
        XCTAssertEqual(direction, 135)
        XCTAssertEqual(CSSPaint.resolvedLocations(three), [0, 0.3, 1])

        guard case .linear(let defaultAngle, _) = CSSPaint(css: "LINEAR-GRADIENT(#fff, #000)") else {
            return XCTFail("Expected a linear gradient without configuration")
        }
        XCTAssertEqual(defaultAngle, 180)

        if case .radial = CSSPaint(css: "radial-gradient(circle, #fff, #000)") {} else { XCTFail("Expected radial") }
        if case .conic(let from, _) = CSSPaint(css: "conic-gradient(from 45deg, #fff, #000)") {
            XCTAssertEqual(from, 45)
        } else {
            XCTFail("Expected conic")
        }
        XCTAssertEqual(CSSPaint(css: "linear-gradient(45deg in oklab, #ff0000 0, #00ff00 100%)")?.primaryColor, .init(red: 1, green: 0, blue: 0))
    }

    func testCSSPaintLocationsFillGaps() {
        let white = CSSPaint.RGBA(red: 1, green: 1, blue: 1)
        let stops = [CSSPaint.Stop(color: white, location: nil), .init(color: white, location: nil), .init(color: white, location: 0.8), .init(color: white, location: nil)]
        XCTAssertEqual(CSSPaint.resolvedLocations(stops), [0, 0.4, 0.8, 1])
    }

    func testFriendlyErrorMessagesLoad() {
        // A duplicated key in the message table crashes the app the first time any error is shown.
        XCTAssertEqual(StoatAPIError.server(statusCode: 400, type: "ShortPassword").errorDescription, "That password is too short.")
        XCTAssertNotNil(StoatAPIError.server(statusCode: 400, type: "SomethingNew").errorDescription)
    }

    func testDecodeInviteLimits() throws {
        let invite = try decode(Invite.self, """
        {"type": "Server", "_id": "abcd1234", "server": "s", "creator": "u", "channel": "c",
         "max_uses": 10, "uses": 3, "expires": "2026-10-01T12:00:00.000Z"}
        """)
        XCTAssertEqual(invite.maxUses, 10)
        XCTAssertEqual(invite.uses, 3)
        XCTAssertEqual(invite.expiryDate, StoatDate.parse("2026-10-01T12:00:00Z"))

        let older = try decode(Invite.self, #"{"type":"Server","_id":"x","server":"s","creator":"u","channel":"c"}"#)
        XCTAssertNil(older.maxUses)
        XCTAssertNil(older.expiryDate)
    }

    func testCreateInvitePayloadLeavesOutUnsetLimits() throws {
        let empty = try JSONEncoder().encode(DeltaAPIClient.CreateInvitePayload())
        XCTAssertEqual(String(decoding: empty, as: UTF8.self), "{}")

        let limited = try JSONEncoder().encode(DeltaAPIClient.CreateInvitePayload(maxUses: 5))
        XCTAssertEqual(String(decoding: limited, as: UTF8.self), #"{"max_uses":5}"#)
    }

    func testPackMarkersAreDroppedBeforeEmoji() {
        XCTAssertEqual(UnicodeEmoji.removingPackMarkers("\u{E0E3}😀 hi"), "😀 hi")
        XCTAssertEqual(UnicodeEmoji.removingPackMarkers("\u{E0E6}🇪"), "🇪")
        // Only markers in front of an emoji are the web client's.
        XCTAssertEqual(UnicodeEmoji.removingPackMarkers("\u{E0E3}a"), "\u{E0E3}a")
    }

    func testLoneRegionalIndicatorsBecomeLetters() {
        XCTAssertEqual(UnicodeEmoji.splittingLoneRegionalIndicators("🇪"), [.letter("E")])
        XCTAssertEqual(UnicodeEmoji.splittingLoneRegionalIndicators("hi 🇳🇿!"), [.text("hi 🇳🇿!")])
        XCTAssertEqual(
            UnicodeEmoji.splittingLoneRegionalIndicators("🇭🇪 🇾"),
            [.letter("H"), .letter("E"), .text(" "), .letter("Y")]
        )
        XCTAssertEqual(UnicodeEmoji.splittingLoneRegionalIndicators("plain"), [.text("plain")])
    }
}
