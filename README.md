# Umbra

A jailbreak tweak that lets you hide conversations in Apple's Messages app.

## How It Works

Umbra removes hidden conversations from your normal Messages list and search results. It does not delete any messages.

## Usage

To hide a conversation, swipe right on it and tap **Hide**. For a pinned conversation, press and hold it and choose **Hide**.

To view your hidden conversations, open Messages search and type:

```text
open umbra
```

To return to your normal conversations, search for:

```text
close umbra
```

While viewing hidden conversations, use the same swipe or press-and-hold menu and choose **Unhide**.

## Compatible Versions

Umbra has been tested on iOS 16.2 with Dopamine and ElleKit. Other iOS versions are not currently guaranteed.

## Installation

### From a .deb (Releases)

1. Download the latest `.deb` from [Releases](../../releases)
2. Install it with Filza or your package manager
3. Respring

### Building from source

Requires [Theos](https://theos.dev/docs/installation).

```bash
git clone https://github.com/liamschwie/Umbra.git
cd Umbra
make package FINALPACKAGE=1
```

The `.deb` will be written to the `packages/` directory. The default build targets rootless jailbreaks.

## Requirements

- Jailbroken iPhone or iPad
- Rootless jailbreak
- ElleKit

## License

This project is made available under the [GNU GPLv3](LICENSE).
