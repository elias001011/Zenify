<div align="center">

# Musify Next

A community fork of [Musify](https://github.com/gokadzev/Musify) focused on stability, desktop support and syncing between your devices.

[![GitHub release](https://img.shields.io/github/v/release/elias001011/Musify-Next?color=2196F3)](https://github.com/elias001011/Musify-Next/releases)
[![License](https://img.shields.io/github/license/elias001011/Musify-Next?color=2196F3)](LICENSE)
[![Based on Musify](https://img.shields.io/badge/based%20on-gokadzev%2FMusify-2196F3)](https://github.com/gokadzev/Musify)
[![Desktop features from Musify Desktop Port](https://img.shields.io/badge/desktop%20features-Musify%20Desktop%20Port-2196F3)](https://github.com/elias001011/Musify-Desktop-Port)

</div>

---

## Why this fork

Musify is a great open source music app, but its future is uncertain: the
original repository received a copyright complaint
([gokadzev/Musify#1012](https://github.com/gokadzev/Musify/discussions/1012))
and it is not clear how long it will stay available.

Musify Next starts from the original code and keeps its infrastructure, while
taking a different direction: a more modern app, first-class desktop support
and stability before new features. The app will get its own name and icon in a
future release; for now it is still Musify.

Version 0.1.0 is the first stable base: upstream Musify plus the desktop
features that were already proven in
[Musify Desktop Port](https://github.com/elias001011/Musify-Desktop-Port).

---

## Features

Everything from Musify:

- Online song search with suggestions
- Offline listening support
- Import & export your data and never lose it
- Custom playlists from a link, and Spotify playlist import
- Listening recaps
- Radio stations
- Synced lyrics
- SponsorBlock support
- Built-in equalizer with presets
- No ads, no subscriptions
- Material UI, accent colors and dynamic colors (Android 12+)
- 21 languages

New in Musify Next:

- **Local Sync**: pair Android, Linux and Windows devices with a PIN and keep
  your liked songs, playlists, history, listening recap, searches and radio
  stations in sync over Wi-Fi. No account or server, encrypted, off by default.
- **Desktop settings**: interface scale that zooms the whole app, start
  maximized and a title bar in the app colors.
- **Keyboard shortcuts** for playback and navigation, all of them remappable.
- **Volume control** in the player, with mute and mouse wheel support.
- **Downloads folder** of your choice on desktop.
- **Built-in updater** for Android, Linux and Windows.
- **Desktop packages**: `.deb`, Windows installer and portable builds.

New features are translated into English and Portuguese for now.

---

## Screenshots

| ![Screenshot 1](fastlane/metadata/android/en-US/images/phoneScreenshots/01.jpg) | ![Screenshot 2](fastlane/metadata/android/en-US/images/phoneScreenshots/02.jpg) | ![Screenshot 3](fastlane/metadata/android/en-US/images/phoneScreenshots/03.jpg) | ![Screenshot 4](fastlane/metadata/android/en-US/images/phoneScreenshots/04.jpg) |
|---|---|---|---|

---

## Download

Get the files for your platform from the
[latest release](https://github.com/elias001011/Musify-Next/releases/latest).

| Platform | File | Notes |
|---|---|---|
| Android | `Musify-arm64-v8a.apk` | Most phones. `Musify.apk` works on every device. |
| Linux (Debian, Ubuntu) | `Musify-linux-x64.deb` | Installs `libmpv` for you. |
| Linux (other) | `Musify-linux-x64.tar.gz` | Needs `libmpv`; run `install-linux-desktop.sh` to add it to your menu. |
| Windows | `Musify-windows-x64-setup.exe` | Lets you choose where data and downloads go. |
| Windows (portable) | `Musify-windows-x64-portable.zip` | No installation. |

Every release includes `SHA256SUMS.txt` to verify the files. iOS is not
supported.

---

## Roadmap

- Own name and icon
- Translations through Crowdin
- A modernized interface

---

## Contribute

Contributions are welcome. Please read the
[contributing guidelines](CONTRIBUTING.md) first.

---

## Credits

- [Musify](https://github.com/gokadzev/Musify) by **Valeri Gokadze** and its
  [contributors](https://github.com/gokadzev/Musify/graphs/contributors): the
  original project this fork is built on. Musify Next would not exist without
  it.
- [Musify Desktop Port](https://github.com/elias001011/Musify-Desktop-Port):
  where the desktop features, Local Sync and packaging of this fork were first
  built and tested.
- [Musify](https://github.com/Harsh-23/Musify) by Harsh-23: the original
  inspiration for the concept and name of Musify.

Musify Next is developed and maintained by
[Elias Juriatti](https://github.com/elias001011).

---

## License

```
Copyright © 2026 Valeri Gokadze
Copyright © 2026 Elias Juriatti and Musify Next contributors

Musify Next is free software licensed under GPL v3.0. You may use, modify, and
distribute this software freely, but must keep the source code open and publicly
available, retain all copyright notices, disclose all changes made, and use the
same GPL v3.0 license.
```

See the [GNU General Public License](LICENSE) for full details.

---

## Disclaimer

```
Musify Next and its contributors do not host, own, or distribute any copyrighted
audio content. The app provides access to content through plugins and external
sources. All trademarks, songs, audio files, and related content remain the
property of their respective owners and are protected by applicable copyright laws.
Included plugins are provided for interoperability and educational purposes only.
Users are solely responsible for ensuring that their use of the app complies with
local laws, copyright regulations, and the terms of service of the respective
content providers. The developers of Musify Next do not encourage or endorse
copyright infringement and assume no liability for misuse of the software or
third-party plugins.
```
