# Yuki (雪)

A native iPhone client for [Stoat](https://stoat.chat), written in SwiftUI for iOS 17 and later.

> Yuki is unofficial. It isn't made, endorsed or supported by Stoat, and using it means Stoat's
> [Terms of Service](https://stoat.chat/legal/terms), [Community Guidelines](https://stoat.chat/legal/community-guidelines)
> and [Privacy Policy](https://stoat.chat/legal/privacy) still apply. Please report Yuki bugs here rather than to Stoat.

## What's in it

- Messaging with markdown, mentions, custom and animated emoji, spoilers, code blocks and LaTeX, plus replies, edits, reactions, pins and search
- Photos, videos and files, with compression to fit Stoat's upload limit, a photo cropper and voice messages you can transcribe on your phone
- Voice and video calls over LiveKit, shown on the system call screen through CallKit
- Server folders and ordering, synced with Stoat for Web
- A notification centre for mentions and DMs across every server
- Server management: roles, permissions, channel overrides, invites, bans, emoji, webhooks and the audit log
- Stoat Discover, a quick switcher (Cmd-K), light and dark themes and custom accent colours

### Known limitations

- **No push notifications.** Stoat's push service only signs notifications for the official app, so Yuki can only notify you while it's running.
- **No screen sharing.** You can watch other people's screen shares, but starting one needs a broadcast extension and a paid developer account.

## Installing

On your iPhone, tap [Add to AltStore](https://yukiapp.xyz/altstore) or [Add to SideStore](https://yukiapp.xyz/sidestore), then install Yuki from the source. You can also add `https://yukiapp.xyz/altstore.json` as a source by hand, or download `Yuki.ipa` from [Releases](https://github.com/Yuki-Client/Yuki-App/releases). New to sideloading? The [install guide](https://yukiapp.xyz/install) walks through it.

## Layout

```
Sources/
  StoatCore/    REST client, gateway, uploads, models, Keychain and disk cache
  StoatState/   AppStore, the normalised store, timelines, read state and permissions
  StoatVoice/   Calls: LiveKit, CallKit and call sounds
  StoatUI/      SwiftUI screens and components
Tests/          Model decoding and store tests
YukiApp/        App entry point, assets and Info.plist
```

Models and routes follow the Stoat backend in [stoatchat/stoatchat](https://github.com/stoatchat/stoatchat).

## Building

Open `Yuki.xcodeproj` in Xcode 26 or later and run the **Yuki** scheme. New files under `Sources/` are picked up automatically; `generate_xcodeproj.py` only needs running again after changing `YukiApp/` or the app's build settings.

To install on a connected iPhone with Developer Mode on:

```bash
./scripts/install-device.sh
```

Apps signed with a free Apple account stop opening after 7 days; run the script again to renew. Tests run with `./scripts/test.sh`, and `./scripts/build-ipa.sh` builds an unsigned `build/Yuki.ipa` for AltStore or SideStore.

## Licence

Copyright © 2026 Aki

Yuki is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License, version 3, as published by the Free Software Foundation. It's distributed without any warranty. See [LICENSE](LICENSE) for the full terms.
