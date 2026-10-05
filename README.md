# PhoneMirror — iOS (sender)

Emit the **whole screen of your iPhone to a Mac over Wi‑Fi**, no cable. This is
the iPhone half: a tiny app plus a **ReplayKit Broadcast Upload Extension** that
captures the whole display, hardware-encodes it and streams it over the local
network with Bonjour.

The Mac half (the viewer) is a separate repo: **PhoneMirror-macOS**.

## Why an app *and* an extension

iOS does not let a normal app capture the system screen — only its own. To mirror
*any* app the user must start a **Broadcast Upload Extension** from Control
Center. That is exactly what every mirroring app does under the hood.

## Build

```sh
brew install xcodegen
xcodegen generate
open PhoneMirror.xcodeproj
```

Select the `PhoneMirrorSend` scheme. The app embeds the `PhoneMirrorBroadcast`
extension.

## Install on the iPhone

A free Apple ID is enough. Build an unsigned `.ipa` and let AltStore re-sign it
(app **and** extension):

```sh
./scripts/make-ipa.sh      # -> build/PhoneMirror.ipa
```

## Use

1. Install `PhoneMirror.ipa` with AltStore.
2. Open **PhoneMirror** and press **Iniciar emisión** — or, from **Control
   Center**, long-press the screen-record button and choose **PhoneMirror**.
3. Open the Mac viewer (same Wi‑Fi).

## Wire protocol

`Shared/WireProtocol.swift`: 12-byte header + `videoFormat`/`videoFrame` messages.
H.264 or HEVC (AVCC), hardware-encoded. The viewer repo speaks the same protocol.

## Notes

- Service type: `_phonemirror._tcp`.
- The sender binds any free port; Bonjour advertises the real one.
- Video only (no audio).

MIT licensed.
