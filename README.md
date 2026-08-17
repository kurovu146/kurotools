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
git clone https://github.com/kurovu146/kurovitals.git
cd kurovitals
./scripts/build-release.sh        # build
./scripts/install-helper.sh       # install the root fan-control daemon (asks for sudo)
./scripts/install-app.sh          # build + sign the bundle, install it to /Applications
```

Then, to have it start at login, turn on **Chạy khi đăng nhập** in *Settings ▸ Chung*. That
toggle is the *only* autostart mechanism: the app registers its own LaunchAgent through
`SMAppService`, using the plist shipped inside the bundle. `install-app.sh` never writes a
LaunchAgent of its own — two competing ones would auto-start two copies at login.

Prefer to run it in the foreground instead of installing it? Skip `install-app.sh` and run:

```bash
make build && .build/debug/KuroTools
```

(Not a bare `swift run` — see [Development](#development) below for why that would silently link a
stale Rust core.)

Removal:

```bash
./scripts/uninstall-app.sh        # quit the app + remove /Applications/KuroTools.app
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
| `KuroTools` | Executable: wires `Vitals` + `Translate` behind one menu bar icon (`AppDelegate`) |

See `docs/superpowers/specs/` (design) and `docs/superpowers/spike-findings.md` (real M2 Pro SMC keys & verification).

## Development

```bash
make build        # cargo build --release (Rust core), then swift build
make test         # cargo test (Rust core, 123 tests), then swift test (65 tests)
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
