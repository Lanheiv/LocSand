# LocSand

Send messages and files to nearby devices over your local Wi-Fi. No accounts, no cloud, no server in the middle.

LocSand is a cross-platform [Flutter](https://flutter.dev) app. Devices on the same network find each other automatically, then talk directly over an encrypted, mutually authenticated connection.

## Features

- **Automatic discovery.** Nearby devices appear on the home screen via UDP broadcast.
- **Chat.** Send text messages directly to a peer.
- **File transfer.** Send files of up to 8 GiB per file. The receiver must accept each file, with live progress on both sides.
- **Saved peers.** Save a device so you can reconnect later and have its connection requests auto-accepted once its identity is verified.
- **Optional chat history.** History is saved per peer, only if you turn it on. You can delete it at any time.
- **Settings.** Display name, light/dark/system theme, auto-discovery on/off, receive folder, and clearing all chat history.

## Security model

LocSand is designed so that other people on the same Wi-Fi cannot impersonate your devices or read your traffic.

- All connections use **TLS**. Each device generates its own RSA-2048 key pair and self-signed certificate on first launch.
- A **device ID is the SHA-256 of the device's public key**, so it cannot be chosen freely. To use an ID, a peer must own the matching private key.
- On top of TLS there is a **signed handshake** (`hello` → `challenge` → `request`). Both sides sign both IDs, both nonces and the hash of the server's TLS certificate. A man-in-the-middle who terminates TLS presents a different certificate, so the signature fails to verify.
- Certificate fingerprints are **pinned on first use**. If a known device later shows a different certificate, the connection is flagged as a mismatch.
- A saved peer is auto-accepted **only after** its signature has been verified.
- Discovery packets are size-limited and rate-limited per source address, so floods are dropped before any parsing.
- Incoming files are written to a temporary `.locsand-part` file and renamed only after the whole file has arrived and been verified. A crash never leaves a half-written file that looks finished.

> The private key is stored in the app's support directory (permissions restricted to the owner on Linux and macOS). Anyone with access to that file can impersonate the device.

## Supported platforms

| Platform | Status |
|----------|--------|
| Android  | Supported (see [Platform setup](#platform-setup)) |
| iOS      | Supported, but UDP broadcast/multicast may need an Apple entitlement. Test on a real device. |
| macOS    | Supported (entitlements required) |
| Windows  | Supported |
| Linux    | Supported |
| Web      | **Not supported.** The app uses `dart:io` sockets (`RawDatagramSocket`, `SecureSocket`), which Flutter Web does not provide. |

## Getting started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) with Dart `^3.13.0`
- Toolchain for your target platform (Android Studio, Xcode, Visual Studio, or GTK/CMake on Linux)

### Run

```bash
git clone https://github.com/Lanheiv/LocSand.git
cd LocSand
flutter pub get
flutter run
```

Pick a target with `-d`, for example `flutter run -d linux`, `-d windows`, `-d macos` or `-d <android/ios device id>`.

To try it out, run the app on **two devices connected to the same Wi-Fi network**. They should show up under **Nearby**.

### Test

```bash
flutter test
```

The tests cover the data models, line framing, device identity, auth protocol, atomic file writes, file naming, chat and file sessions, and the UDP and TCP layers (including real TLS pairs).

## Configuration

Network settings live in [`assets/config.toml`](assets/config.toml):

```toml
[node]
name = "User"                  # default display name (can be changed in Settings)

[network]
udp_port = 5000                # discovery
tcp_port = 5001                # chat and file transfer
multicast_port = 5002

[discovery]
broadcast_address = "255.255.255.255"
enabled = true
```

If devices cannot see each other, make sure the UDP and TCP ports above are not blocked by a firewall.

## Platform setup

Some platform files need manual configuration before release builds work. Full details are in [`docs/PLATFORM_FIXES.md`](docs/PLATFORM_FIXES.md). Summary:

- **Android:** add the `INTERNET`, `ACCESS_NETWORK_STATE` and `ACCESS_WIFI_STATE` permissions to `AndroidManifest.xml`, and set a real application ID and release signing config. Keep `key.properties` and `*.jks` out of Git.
- **iOS:** add `NSLocalNetworkUsageDescription` to `Info.plist`.
- **macOS:** enable the app sandbox with network client/server and file access entitlements. The default receive folder is Downloads, so the Downloads entitlement is needed.
- **Windows:** allow access on private networks when the Firewall prompts on first launch.

## Troubleshooting

**No devices appear under "Nearby"**
- Both devices must be on the same LAN. Guest Wi-Fi networks often isolate clients and block discovery.
- Check that the UDP and TCP ports from `config.toml` are open.
- Check that **Auto discovery** is enabled in Settings.
- Pull down on the home screen to search again.

**"Networking could not start"**
The TCP port is probably already in use. Close the other program or change `tcp_port` in `config.toml`.

## Project structure

```
lib/
├── main.dart                 # App entry point, starts networking
├── src/
│   ├── core_protocols.dart   # Boots config, identity, TCP server, UDP discovery
│   ├── data/                 # Models: chat messages, file transfers, peers, session state
│   ├── helpers/              # Crypto/auth, certs, identity, stores, config, framing
│   ├── session/              # Chat, file transfer and saved-peer logic
│   └── tasks/                # UDP discovery, TCP server, TCP client connection
└── view/                     # UI: home, chat screen, settings, components
assets/config.toml            # Ports and discovery settings
docs/PLATFORM_FIXES.md        # Per-platform setup notes
test/                         # Unit and integration tests
```

## Dependencies

`permission_handler`, `fluttertoast`, `toml`, `basic_utils`, `path_provider`, `file_picker`, `crypto`, `cupertino_icons`

## License

No license has been specified yet. Add a `LICENSE` file to let others know how they may use this project.
