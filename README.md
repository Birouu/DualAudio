# DualAudio

A tiny macOS menu bar app that lets you send audio to **two (or more) output
devices at the same time** — e.g. two Bluetooth headphones, or AirPods +
your Mac's speakers — something macOS doesn't offer out of the box the way
iOS does with AirPods audio sharing.

## Install

1. Download `DualAudio.dmg` (or build it yourself — see below).
2. Open the DMG and drag **DualAudio.app** into **Applications**.
3. Since this app isn't notarized (no Apple Developer ID), macOS Gatekeeper
   will block a normal double-click the first time. Instead:
   - **Right-click** `DualAudio.app` → **Open** → click **Open** again in
     the warning dialog. You only need to do this once.
   - If macOS says the app "is damaged and can't be opened," run this once
     in Terminal instead:
     ```
     xattr -cr /Applications/DualAudio.app
     ```
4. Launch it. A speaker icon appears in the menu bar — no Dock icon.

## Use

Click the menu bar icon to see every available audio output device.

- Check **one** device to make it the sole output.
- Check **two or more** to play the same audio out of all of them at once.
- When two or more are active, a **"Volume (all)"** slider appears along
  with one slider per device — the master slider moves everything together,
  each device's own slider lets you trim just that one down.
- **Launch at Login** and **Quit** are at the bottom of the menu.

The app remembers your combo across quits, relaunches, and even crashes —
it detects an active combo on startup and restores it automatically.

## Build from source

Requires Xcode (or at least the Swift toolchain) on macOS 13+.

```bash
git clone https://github.com/Birouu/DualAudio.git
cd DualAudio
./build_app.sh
```

This builds a release binary and installs `DualAudio.app` to
`~/Applications`. Open it from there, or run `open ~/Applications/DualAudio.app`.

To package a distributable DMG after building:

```bash
./build_dmg.sh
```

This produces `DualAudio.dmg` in the project folder.

## How it works

macOS has no built-in "play to two Bluetooth devices" feature, but it does
support combining outputs into a **Multi-Output Device** (normally created
manually in Audio MIDI Setup). DualAudio creates and manages one of these
programmatically via CoreAudio whenever you select multiple devices, and
tears it down when you're back to a single device.

## Known limitations

- Not notarized — see the Gatekeeper workaround above.
- Two Bluetooth devices don't share a hardware clock, so very long listening
  sessions can drift slightly out of sync (a macOS/Bluetooth limitation, not
  something software can fully fix).
- Bluetooth audio occasionally needs a beat to fully attach when a combo is
  first created; the app detects this and automatically rebuilds the combo
  once if needed.
