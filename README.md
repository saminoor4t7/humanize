# Humanize

Offline, encrypted file transfer between Windows and Android devices on the same LAN. Flutter, MVVM (Provider).
See `docs/ARCHITECTURE.md` for layers, protocol and security design.

> **Status:** Windows and Android targets are included. Verify builds and transfers on both platforms in your environment.

## 1. Prerequisites
* Flutter stable (3.24+), `flutter config --enable-windows-desktop`
* Windows: Visual Studio 2022 with "Desktop development with C++"
* Android: Android SDK and an Android device or emulator
* Check with `flutter doctor`

## 2. First-time setup
The Windows and Android runners are included. In the folder that contains `pubspec.yaml`:
```powershell
flutter pub get
flutter analyze
flutter test
```

## 3. Run (debug)
```powershell
flutter run -d windows
# list connected devices, then launch on the Android device ID shown
flutter devices
flutter run -d DEVICE_ID
```
On first start Humanize generates a 2048-bit RSA identity (a few seconds, in a background isolate).

## 4. Release build
```powershell
flutter build windows --release
flutter build apk --release
```
Output: `build\windows\x64\runner\Release\` (the .exe, `flutter_windows.dll`, `data\`, plugin DLLs).
Copy the **whole folder**; the .exe does not work alone.
Android APK output: `build\app\outputs\flutter-apk\app-release.apk`.

## 5. Windows Firewall (required on every computer)
Humanize listens on **TCP 52525** (changeable in Settings) and uses **UDP 52526** for discovery.
Allow both on the **Private** profile and only from the local subnet. In an elevated PowerShell:
```powershell
$exe = "C:\Program Files\Humanize\humanize.exe"   # your install path
New-NetFirewallRule -DisplayName "Humanize TCP" -Direction Inbound -Protocol TCP -LocalPort 52525 `
  -Program $exe -Profile Private -RemoteAddress LocalSubnet -Action Allow
New-NetFirewallRule -DisplayName "Humanize Discovery" -Direction Inbound -Protocol UDP -LocalPort 52526 `
  -Program $exe -Profile Private -RemoteAddress LocalSubnet -Action Allow
```
If you change the port in Settings, update the TCP rule. If the network is classified "Public", either set it
to Private or add `Public` to `-Profile` knowingly. Never open these ports to the internet; the app also
refuses non-private addresses by itself.

## 6. Packaging for company computers
1. Build release, copy `Release\` to a staging folder.
2. **Installer (recommended):** compile `installer\humanize.iss` with [Inno Setup](https://jrsoftware.org/isinfo.php).
   It installs to `Program Files\Humanize`, adds a Start-menu shortcut and creates the two firewall rules.
3. **No installer:** zip the `Release` folder, unzip on each PC, run the firewall commands above once.
4. Silent install for IT: `HumanizeSetup.exe /VERYSILENT /SUPPRESSMSGBOXES`.
5. "Launch at startup" in Settings writes a per-user `HKCU\...\Run` entry (no admin needed).
6. If the Visual C++ runtime is missing on a fresh PC, install the "VC++ 2015-2022 x64 Redistributable".

## 7. Tests
```powershell
flutter test                                  # everything
flutter test test/transfer_loopback_test.dart # real TLS transfers over 127.0.0.1
```
Covered: protocol framing and partial reads, path/filename safety, SHA-256, discovery duplicates/validation,
settings, TLS connection, Unicode/space names, empty files, 64 MiB files, concurrent transfers, declined and
oversized requests, wrong identity, raw non-TLS client, interruption, **resume**, corrupted partial,
receiver going offline, and user cancel. The loopback file takes a while because RSA keys are generated
in pure Dart (a few seconds each).

## 8. Testing between Windows and Android devices
1. Both devices on the same network/subnet (no VPN, no guest Wi-Fi with client isolation).
2. Install/run Humanize on both. On Windows, add the firewall rules (section 5). Android grants network access through the app manifest.
3. **Dashboard** on each: LAN IP shown and "Receiving on port 52525". 
4. **Devices** > Refresh: the other PC should appear within ~5 s. If not, use **Add by IP** (this also proves
   TCP + TLS + identity work even when broadcasts are blocked).
5. Compare the **device ID** (About page on one PC vs Devices page on the other) before pressing "Trust".
6. **Send**: add files and a folder, pick the device, Send. On the receiver, **Receive** shows the request:
   Accept. Check progress, MB/s, ETA, then compare the received file hash:
   `Get-FileHash <file> -Algorithm SHA256` on both PCs.
7. Resume: start a multi-GB send, unplug the network cable or kill the app on the sender at ~50 %, reconnect,
   send the same files again: the card shows "Resumed: X were already received".
8. Cancel from each side; reject a request; send a file bigger than the receiver's limit; send to a wrong IP.
9. Measure speed with a large file (e.g. 4 GB). Expect the lower of your network and disk speeds; try
   chunk sizes 256 KB / 1 MB / 4 MB in Settings.

## 9. Known limitations (be aware before production use)
* Cross-device transfer should be validated on physical Windows and Android devices, especially across vendor-specific Android network restrictions.
* Discovery assumes /24 subnets for directed broadcast and needs UDP broadcast allowed; Add-by-IP is the fallback.
* TLS speed in Dart is CPU-bound; very fast (10 GbE) links may not be saturated.
* IPv4 only. No transfer of symbolic links; empty folders are not sent (only files).
* Private key is stored in the app-support folder unencrypted (protected by the Windows user profile ACLs);
  DPAPI/Credential Locker storage is a possible hardening step.
* SHA-256 of a file is computed while sending, so a file that changes during sending is detected, not repaired.
* Launch-at-startup is available on Windows only. Android may restrict background receiving while the app is closed or suspended.
