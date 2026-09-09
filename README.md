# Umbra

A jailbreak tweak that hides selected conversations from Apple's Messages app behind a private inbox.

## Features

- Hide individual conversations without deleting their message history
- Keep hidden conversations out of the normal conversation list and search results
- Support both regular and pinned conversations
- Mute a conversation while it is hidden and restore its previous alert state when it is unhidden
- Persist the hidden list across app launches, resprings, and reboots
- Automatically return to the normal inbox when Messages enters the background

## Usage

### Hiding a conversation

- For a regular conversation, swipe right and tap **Hide**.
- For a pinned conversation, touch and hold it and select **Hide** from the context menu.

### Opening the hidden inbox

Open Messages search and type:

```text
open umbra
```

The search interface closes automatically and the conversation list switches to the hidden inbox. To return to the normal inbox, search for:

```text
close umbra
```

You can also toggle the hidden inbox by tapping once and then holding a second touch on the center of the Messages navigation bar.

### Unhiding a conversation

While the hidden inbox is open, swipe right on a conversation and tap **Unhide**, or use **Unhide** in its context menu if it is pinned.

## Compatible Versions

Umbra has been developed and tested on iOS 16.2 with a rootless Dopamine/ElleKit environment. It uses private ChatKit APIs whose names and behavior can change between iOS releases, so other versions are not currently guaranteed.

The measured iOS 16.2 private-API map and redacted runtime probes are included in [`docs/compat-map.md`](docs/compat-map.md) and [`probe/`](probe/).

## Installation

### From a .deb (Releases)

1. Download the latest `.deb` from [Releases](../../releases)
2. Transfer it to your device and install it with Filza or your package manager
3. Restart the Messages app or respring

### Building from source

Requires [Theos](https://theos.dev/docs/installation).

```bash
git clone https://github.com/liamschwie/Umbra.git
cd Umbra
make package FINALPACKAGE=1
```

The `.deb` will be written to the `packages/` directory. The default build targets rootless jailbreaks.

## How It Works

Umbra stores only ChatKit's opaque conversation identifiers and the conversations' previous mute state. It filters Messages' diffable conversation-list snapshots and search-result arrays at runtime, leaving the underlying message database untouched.

When a conversation is hidden, Umbra sets its mute date to the same indefinite value Messages uses. When it is unhidden, Umbra restores the exact mute state it recorded before hiding it.

## Important Limitations

- Umbra hides conversations from the Messages interface; it does not encrypt, delete, or move the underlying messages.
- The Messages application icon badge may still include unread messages from hidden conversations.
- Hiding a one-to-one conversation does not automatically hide group chats containing that person. Each group conversation must be hidden separately.
- A group chat that Messages recreates with a new internal identifier may reappear and need to be hidden again.
- Compatibility outside the tested iOS 16.2 environment is not yet verified.

## Requirements

- Jailbroken iPhone or iPad
- iOS 15.0 or later
- ElleKit

## License

This project is made available under the [GNU GPLv3](LICENSE).
