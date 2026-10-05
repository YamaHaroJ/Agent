# Clock Art Bridge

A lightweight macOS helper for the iPad Clock project.

## What it does

- Runs a tiny Now Playing reader inside Apple's `/usr/bin/perl` host so
  macOS 15.4+ MediaRemote returns system Now Playing metadata and artwork.
- Uses MediaRemote change notifications rather than continuously processing
  audio or video.
- Exposes the latest state on a tiny local HTTP server:
  - `/status`
  - `/artwork`
- Advertises `_clockart._tcp` over Bonjour for a future zero-config iPad
  client.

The Mac is **not** screen-capturing or analyzing audio. Between track changes,
the bridge should be essentially idle.

## First test

Run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YamaHaroJ/Agent/main/full-screen-clock/mac-bridge/install-bridge.sh)
```

For iPad-originated playback, route the iPad's audio output to the Mac using
AirPlay first. The bridge then sees the Now Playing session received by macOS.

Keep the Terminal window open during the first test. The installer prints both
the Mac's IP URL and its stable `.local` hostname.
