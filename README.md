# KuroTools

A native macOS **menu bar** app (Swift) that monitors **CPU temperature, CPU load, RAM, and fan RPM**
and lets you control each fan's speed independently, and also pops up a **dictionary lookup** for
whatever text is currently selected in any app (global hotkey) — built for **Apple Silicon (MacBook
Pro M2 Pro)**.

The menu bar shows a single **`K`** icon; click it for the full readout and controls:

```
K  ▾
 ├ CPU temp: 64°C
 ├ CPU load: 12%
 ├ RAM: 9.7 / 16 GB
 ├ Quạt 1: 2400 rpm (auto)        ▸  Auto · 2500 · 3000 · … · Max
 ├ Quạt 2: 2500 rpm → đặt 5000    ▸  Auto · 2500 · … · [5000 ✓] · … · Max
 ├ Tất cả Auto · Quiet · Max
 ├ Tiến trình...                  opens CPU/RAM process inspector
 └ Settings · Quit
```

## Features

- **Compact menu bar:** just a `K` icon — all metrics live in the click dropdown.
- **Live metrics:** CPU temperature (avg of P-core + E-core sensors), CPU load, RAM used
  (matches Activity Monitor's *Memory Used* = App Memory + wired + compressed), and per-fan RPM.
- **Independent per-fan control:** each fan gets its own submenu of RPM presets (500-rpm steps)
  plus *Auto*; a ✓ marks the requested target. Global *Tất cả Auto / Quiet / Max* too.
  *(macOS menus can't host a text field that receives typing, so speed is chosen from presets.)*
- **Process inspector:** search running processes by name/PID/port, view per-process CPU/RAM
  and open ports, and send a terminate signal to a selected process.
- **Dictionary lookup popup:** global hotkey captures the current text selection in any app and
  shows source + Oxford English definitions + Vietnamese translation in a floating panel.
- **Video wallpaper + screensaver:** pick any video (Settings ▸ Chung ▸ Hình nền video) and it plays,
  muted and looping, as the desktop wallpaper — behind the icons, on every Space, click-through.
  The same video doubles as a real macOS screensaver (`KuroToolsWallpaper.saver`, installed with
  `./scripts/install-saver.sh`). A toggle in the menu bar (`Hình nền video`) switches the wallpaper
  on/off without opening Settings.
- **Safety, three layers:** RPM is clamped to the hardware range; the app auto-reverts to Auto
  when temperature hits the threshold (90/95/100 °C, with a menu-bar warning); the root helper
  reverts every fan to Auto if the app crashes / stops sending heartbeats — and on its own startup.
- **Runs in the background** and starts at login (via a LaunchAgent).

## Requirements

- Apple Silicon Mac with a fan (developed/verified on **MacBook Pro 14" M2 Pro**, macOS 26).
- Xcode toolchain (Swift 6.x) **and** a Rust toolchain (`cargo`) — the `Translate` module bridges
  a Rust core (`crates/`) over the C ABI. No third-party Swift package dependencies.

> Reading sensors needs no privileges. **Controlling the fan writes to the SMC, which requires
> root**, so fan control runs through a small privileged LaunchDaemon (installed once). The app
> still monitors fine without it — fan controls just show "⚠︎ Helper chưa cài?" until it's installed.

## Install

```bash
git clone https://github.com/kurovu146/kurotools.git
cd kurotools
./scripts/build-release.sh        # build
./scripts/install-helper.sh       # install the root fan-control daemon (asks for sudo)
./scripts/install-app.sh          # build + sign the bundle, install it to /Applications
```

Then, to have it start at login, turn on **Chạy khi đăng nhập** in *Settings ▸ Chung*. That
toggle is the supported autostart mechanism: the app registers its own LaunchAgent through
`SMAppService`, using the plist shipped inside the bundle. `install-app.sh` never writes a
LaunchAgent of its own — two competing ones would auto-start two copies at login.

> **A hand-installed LaunchAgent shadows the toggle.** `SMAppService` only ever sees the plist
> inside the bundle, so a file in `~/Library/LaunchAgents` carrying the *same* label
> (`com.kuro.kurotools.app`) is invisible to it: the toggle can read **off** while launchd really
> does start the app at login, and turning the toggle on registers a second definition of one
> label. Check with:
>
> ```bash
> ls ~/Library/LaunchAgents/com.kuro.kuro*.app.plist
> ```
>
> Anything listed there is stale and should go — `install-app.sh` and `uninstall-app.sh` remove
> both known labels (`com.kuro.kurotools.app` and the older `com.kuro.kurovitals.app`), after
> which the toggle is the whole story.

Prefer to run it in the foreground instead of installing it? Skip `install-app.sh` and run:

```bash
make build && .build/debug/KuroTools
```

(Not a bare `swift run` — see [Development](#development) below for why that would silently link a
stale Rust core.)

Removal:

```bash
./scripts/uninstall-app.sh        # quit the app, remove /Applications/KuroTools.app, any
                                  # hand-written LaunchAgent, the .saver bundle, and the
                                  # video copied into the screensaver's container
./scripts/uninstall-helper.sh     # remove the root helper (fans return to system Auto)
```

> Turn the login-item toggle **off before** uninstalling: only the app itself can call
> `SMAppService.unregister()`, so deleting the bundle first leaves a dangling "not found" entry in
> *System Settings ▸ General ▸ Login Items*.
>
> The installed app runs from `/Applications`, not from the repo — but `install-helper.sh` still
> installs the helper out of `./.build/release/`, so keep the repo folder. After pulling new code,
> re-run `install-helper.sh` (the GUI↔helper protocol may have changed) and `install-app.sh`.

## Usage

Click the **`K`** in the menu bar:

- **Per fan** → open *Quạt 1* / *Quạt 2* → pick an RPM (or *Auto*). Each fan is independent;
  the title shows the current speed and, when forced, the requested target (`→ đặt 5000`).
- **Tất cả Auto / Quiet / Max** apply to all fans at once.
- **Tiến trình...** opens a searchable process list with PID, ports, CPU, RAM, refresh, and kill controls.
- **Settings** → toggle which metric rows appear, or set the over-temp auto-revert threshold.
- **Quit** reverts all fans to Auto and exits.

## Video wallpaper

The wallpaper video is a borderless window placed at macOS's *desktop* window level — behind the
desktop icons, invisible to clicks, present on every Space (including fullscreen app spaces).
It is driven by `AVQueuePlayer` + `AVPlayerLooper` (muted), and App Nap is disabled while it runs
so playback never stutters; idle sleep is *not* blocked, so the Mac still sleeps normally.

Pick the video in *Settings ▸ Chung ▸ Hình nền video*, toggle it there or from the menu bar
(*Hình nền video*). If the video file is deleted or moved, the wallpaper stops itself.

### Screensaver

`./scripts/install-saver.sh` builds `KuroToolsWallpaper.saver` and installs it into
`~/Library/Screen Savers/`; pick *KuroTools Video* in System Settings ▸ Screen Saver.

Third-party screensavers run sandboxed inside `legacyScreenSaver`, so the app and the saver cannot
share preferences — measured on 2026-08-29: the same `UserDefaults` suite resolves to two different
plists. The bridge is therefore a single file: the app copies the chosen video to
`~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support/KuroTools/screensaver-video.<ext>`,
and the saver reads that file from inside its own container. No video there yet → the saver draws a
black screen pointing back at Settings.

The screensaver is *not* the lock screen: macOS gives third-party bundles no way to draw there, so
playback stops when the Mac actually locks.

## Architecture

Two processes, split by privilege:

```
┌─────────────────────────┐      Unix socket (JSON)       ┌──────────────────────┐
│  KuroTools.app (user)   │ ──── set fan N = 5000 rpm ───▶ │ kurovitals-helper    │
│  • "K" menu bar + menu   │ ◀─── ok / state ──────────────│  (root LaunchDaemon) │
│  • CPU%/RAM via Mach     │                               │  • writes SMC F{n}Md/Tg │
│  • temp/fan via SMC (RO) │                               │  • per-fan TTL watchdog │
└─────────────────────────┘                               └──────────────────────┘
```

Swift Package Manager modules:

| Module | Responsibility |
|---|---|
| `SMCKit` | IOKit `AppleSMC` read/write, typed value decoding (`flt`/`fpe2`/`ui8`/…), per-fan helpers |
| `SystemStats` | CPU load (`host_statistics`), memory (`vm_statistics64`, App-Memory model), process list/ports/kill |
| `SensorReader` | Combines temp (avg of `Tp*`+`Te*`) / CPU / RAM / per-fan readings into a `Snapshot` |
| `FanControl` | Per-fan clamp + over-temp auto-revert + heartbeat; Unix-socket `HelperClient` |
| `HelperProtocol` | Shared `Codable` command/response + socket path |
| `Vitals` | AppKit menu bar UI (`VitalsController`, `MenuBarController`), settings, process inspector |
| `kurovitals-helper` | Root daemon: applies per-fan SMC writes, per-fan TTL watchdog |
| `Translate` | Swift↔Rust bridge (`crates/ktranslate-core`/`ktranslate-ffi` over the C ABI): text capture, lookup, language config, saved words, TTS |
| `Wallpaper` | Desktop-level video wallpaper windows (`VideoWallpaperController`), the app's own settings store, and `SaverVideoInstaller` (copies the chosen video into the screensaver's container) |
| `WallpaperSaver` | The `.saver` bundle's principal class (`KTWallpaperSaverView`) + video locator |
| `KuroTools` | Executable: wires `Vitals` + `Translate` + `Wallpaper` behind one menu bar icon (`AppDelegate`) |

See `docs/superpowers/specs/` (design) and `docs/superpowers/spike-findings.md` (real M2 Pro SMC keys & verification).

## Development

```bash
make build        # cargo build --release (Rust core), then swift build
make test         # cargo test (Rust core, 131 tests + 1 live-network test that stays
                  # ignored), then swift test (229 tests)
```

Always go through `make` — never call `swift build`/`swift test` directly. SwiftPM does not treat
`crates/target/release/libktranslate_ffi.a` as a build input: after editing the Rust core, a bare
`swift build` reports "Build complete" in well under a second and **silently keeps running the old
Rust binary**, with no warning and no error. `make rust` (a dependency of every target above)
hashes the `.a` and forces a clean Swift rebuild only when it actually changed, so a normal
no-op build stays fast.

**Xcode gap:** building or testing from Xcode also bypasses the Makefile — Xcode has no idea the
Rust core exists. If you use Xcode, run `make rust` by hand first, and again after every Rust
change, before hitting Build/Test.

Diagnostics (read SMC keys; `--test-high` requires sudo and spins the fans up to verify control):

```bash
swift run smc-dump                       # dump fan/temp keys
sudo .build/debug/smc-dump --test-high   # force ~5500 rpm and read back actual RPM
sudo .build/debug/smc-dump --revert      # safety: force fans back to Auto
```

## Notes

Fan control is unsupported by Apple and reverse-engineered via SMC keys. It was empirically
verified on the target M2 Pro (actual RPM climbed to the requested target). The physical fan
takes a few seconds to spin up to a new target — that lag is mechanical, not software. Use at
your own risk; firmware thermal throttling remains the ultimate hardware protection.
