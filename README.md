# KuroVitals

A native macOS **menu bar** app (Swift) that monitors **CPU temperature, CPU load, RAM, and fan RPM**, and lets you control each fan's speed independently — built for **Apple Silicon (MacBook Pro M2 Pro)**.

The menu bar shows a single **`K`** icon; click it for the full readout and controls:

```
K  ▾
 ├ CPU temp: 64°C
 ├ CPU load: 12%
 ├ RAM: 9.7 / 16 GB
 ├ Quạt 1: 2400 rpm (auto)        ▸  Auto · 2500 · 3000 · … · Max
 ├ Quạt 2: 2500 rpm → đặt 5000    ▸  Auto · 2500 · … · [5000 ✓] · … · Max
 ├ Tất cả Auto · Quiet · Max
 └ Settings · Quit
```

## Features

- **Compact menu bar:** just a `K` icon — all metrics live in the click dropdown.
- **Live metrics:** CPU temperature (avg of P-core + E-core sensors), CPU load, RAM used
  (matches Activity Monitor's *Memory Used* = App Memory + wired + compressed), and per-fan RPM.
- **Independent per-fan control:** each fan gets its own submenu of RPM presets (500-rpm steps)
  plus *Auto*; a ✓ marks the requested target. Global *Tất cả Auto / Quiet / Max* too.
  *(macOS menus can't host a text field that receives typing, so speed is chosen from presets.)*
- **Safety, three layers:** RPM is clamped to the hardware range; the app auto-reverts to Auto
  when temperature hits the threshold (90/95/100 °C, with a menu-bar warning); the root helper
  reverts every fan to Auto if the app crashes / stops sending heartbeats — and on its own startup.
- **Runs in the background** and starts at login (via a LaunchAgent).

## Requirements

- Apple Silicon Mac with a fan (developed/verified on **MacBook Pro 14" M2 Pro**, macOS 26).
- Xcode toolchain (Swift 6.x). No third-party dependencies.

> Reading sensors needs no privileges. **Controlling the fan writes to the SMC, which requires
> root**, so fan control runs through a small privileged LaunchDaemon (installed once). The app
> still monitors fine without it — fan controls just show "⚠︎ Helper chưa cài?" until it's installed.

## Install

```bash
git clone https://github.com/kurovu146/kurovitals.git
cd kurovitals
./scripts/build-release.sh        # build
./scripts/install-helper.sh       # install the root fan-control daemon (asks for sudo)
./scripts/install-app.sh          # run in the background + start at login
```

Prefer to run it in the foreground instead of the background? Skip `install-app.sh` and run:

```bash
swift run KuroVitals
```

Removal:

```bash
./scripts/uninstall-app.sh        # stop the background app + remove autostart
./scripts/uninstall-helper.sh     # remove the root helper (fans return to system Auto)
```

> The scripts run the binaries from `./.build/release/`, so keep the repo folder. After pulling
> new code, re-run `install-helper.sh` (the GUI↔helper protocol may have changed) and
> `install-app.sh`.

## Usage

Click the **`K`** in the menu bar:

- **Per fan** → open *Quạt 1* / *Quạt 2* → pick an RPM (or *Auto*). Each fan is independent;
  the title shows the current speed and, when forced, the requested target (`→ đặt 5000`).
- **Tất cả Auto / Quiet / Max** apply to all fans at once.
- **Settings** → toggle which metric rows appear, or set the over-temp auto-revert threshold.
- **Quit** reverts all fans to Auto and exits.

## Architecture

Two processes, split by privilege:

```
┌─────────────────────────┐      Unix socket (JSON)       ┌──────────────────────┐
│  KuroVitals.app (user)  │ ──── set fan N = 5000 rpm ───▶ │ kurovitals-helper    │
│  • "K" menu bar + menu   │ ◀─── ok / state ──────────────│  (root LaunchDaemon) │
│  • CPU%/RAM via Mach     │                               │  • writes SMC F{n}Md/Tg │
│  • temp/fan via SMC (RO) │                               │  • per-fan TTL watchdog │
└─────────────────────────┘                               └──────────────────────┘
```

Swift Package Manager modules:

| Module | Responsibility |
|---|---|
| `SMCKit` | IOKit `AppleSMC` read/write, typed value decoding (`flt`/`fpe2`/`ui8`/…), per-fan helpers |
| `SystemStats` | CPU load (`host_statistics`), memory (`vm_statistics64`, App-Memory model) |
| `SensorReader` | Combines temp (avg of `Tp*`+`Te*`) / CPU / RAM / per-fan readings into a `Snapshot` |
| `FanControl` | Per-fan clamp + over-temp auto-revert + heartbeat; Unix-socket `HelperClient` |
| `HelperProtocol` | Shared `Codable` command/response + socket path |
| `KuroVitals` | AppKit menu bar UI (`AppDelegate`, `MenuBarController`), settings |
| `kurovitals-helper` | Root daemon: applies per-fan SMC writes, per-fan TTL watchdog |

See `docs/superpowers/specs/` (design) and `docs/superpowers/spike-findings.md` (real M2 Pro SMC keys & verification).

## Development

```bash
swift build      # build all targets
swift test       # 20 unit tests (SMC decoders/encoders, stats math, fan logic, sensor aggregation)
```

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
