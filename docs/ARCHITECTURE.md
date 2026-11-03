# Humanize: MVVM Architecture and Data Flow

App name: **Humanize** (offline LAN file transfer for Windows and Android, Flutter + Provider).

## Layers (dependencies point down only)

| Layer | Folder | Responsibility |
|---|---|---|
| **View** | `lib/views`, `lib/widgets` | Draw UI, forward user events. No business logic, no direct service calls. |
| **ViewModel** | `lib/viewmodels` | `ChangeNotifier` state, validation, orchestration. No widgets/BuildContext. |
| **Service** | `lib/services` | All I/O: TLS/TCP, UDP discovery, files, crypto, persistence. No UI. |
| **Model** | `lib/models` | Plain data classes. |
| **Core** | `lib/core` | Theme, constants, exceptions, pure utilities. |

## Data flow

```
 user action             method call               I/O
┌──────────┐ event  ┌──────────────┐  call   ┌──────────────┐
│   View   │ ─────▶ │  ViewModel   │ ──────▶ │   Service    │ ─▶ socket / disk
└──────────┘        └──────────────┘         └──────────────┘
     ▲                     ▲  │                      │
     │ notifyListeners()   │  └──── Model ◀──────────┘
     └─────────────────────┘      streams (changes / events / devices)
```

### Example: sending a file
1. `SendView` -> `SendViewModel.pickFiles()` (file_picker) -> list of `SendFile` models.
2. "Send" -> `SendViewModel.sendToSelected()` -> `TransferViewModel.send()` -> `FileTransferService.send()`.
3. Service queues a `Transfer` (respecting max concurrent transfers) and runs a `TransferSender`:
   TLS connect -> `PeerHandshake` (mutual signed auth) -> `TRANSFER_REQUEST`.
4. Receiver `IncomingSession` validates every path, asks the user via `FileTransferService.requestApproval`
   (shown on `ReceiveView` through `TransferViewModel.pendingRequests`), then answers `TRANSFER_RESPONSE`
   with resume info.
5. Chunks stream with backpressure; progress updates mutate the `Transfer` and the service emits a
   throttled `changes` event (about 10/s). ViewModels call `notifyListeners()`, Views rebuild.
6. Receiver verifies size + SHA-256, renames the `.part` file into place, replies `FILE_RESULT`.
7. Service writes a `TransferRecord` to `HistoryService`; `HistoryViewModel` and the dashboard update.

## Wire protocol v1

Frame: `u32 length (big endian, includes type byte) | u8 type | payload`.
Control frames carry UTF-8 JSON (max 1 MiB); `CHUNK` frames carry raw bytes (max 8 MiB).
The reader loops until it has exactly N bytes, so partial reads, glued frames and split headers are handled.

| Type | Dir | Purpose |
|---|---|---|
| HELLO / CHALLENGE / AUTH / AUTH_OK | both | mutual authentication inside TLS |
| TRANSFER_REQUEST | C→S | manifest: id, files (key, relPath, size) |
| TRANSFER_RESPONSE | S→C | accepted/rejected + per-file resume `{offset, sha256-of-prefix}` |
| FILE_START / CHUNK / FILE_END | C→S | `{index, offset}` / bytes / `{index, size, sha256}` |
| FILE_RESULT | S→C | `{ok, error}` after verification |
| SESSION_DONE, CANCEL, ERROR | any | end / abort / failure |

## Security model

* **Encryption**: TLS over TCP. Each device has a self-signed certificate made from its own RSA key.
* **Identity**: device ID = SHA-256 of the RSA public key. Both sides sign a challenge that includes both
  nonces **and the server's TLS certificate fingerprint**, so a man in the middle with another
  certificate fails verification. Self-signed certs are only accepted because this handshake follows.
* **Trust is explicit**: discovery and LAN membership prove nothing. Unknown devices always need
  per-transfer approval. "Trusted" devices (user choice, keyed by device ID) may skip approval only when
  the user enables that policy (off by default).
* **Writes**: names validated (no `..`, absolute paths, drive letters, reserved names, bad characters);
  resolved inside the download folder; data goes to `.humanize-partial/` with names built from hex IDs;
  final rename only after SHA-256 verification; existing files are never overwritten.
* **Network scope**: client and server both refuse non-private/loopback IPv4 addresses.
* **No execution**: received files are never opened or run.

## Resume

Receiver keeps `<senderId16>_<fileKey32>.part/.json` in `.humanize-partial`. `fileKey` = SHA-256 of
`relPath|size|modifiedMs`, so re-sending the same unchanged selection resumes. The receiver reports
`{offset, sha256(first offset bytes)}`; the sender hashes its own first `offset` bytes and resumes only on
an exact match, otherwise restarts at 0. Partials older than 7 days are purged; user cancel deletes them.

## Composition (`main.dart`)

```
SettingsService ─▶ SettingsViewModel ─┬▶ TransferViewModel ◀─ FileTransferService ◀─ SecurityService, TrustStore, HistoryService
                                      ├▶ DeviceViewModel   ◀─ DiscoveryService, TrustStore
                                      ├▶ HistoryViewModel  ◀─ HistoryService
                                      ├▶ SendViewModel     ◀─ Transfer/Device VMs
                                      └▶ DashboardViewModel ◀─ all of the above
```
