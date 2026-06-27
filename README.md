# KuroVitals

A native macOS **menu bar** app (Swift) that shows live **CPU temperature, CPU load, RAM, and fan RPM**, and lets you set a specific fan speed — built for **Apple Silicon (MacBook Pro M2 Pro)**.

```
 48° 13% 9.1G 🌀2400
```

## Features

- Live readout in the menu bar: CPU temp (°C), CPU load (%), RAM (GB), fan RPM.
- Manual fan control: type an exact RPM, or use **Quiet / Max / Auto** presets.
- Per-item toggles + adjustable over-temp threshold (90/95/100 °C) in the dropdown.
- **Safety, three layers:** RPM clamped to the hardware range; auto-revert to Auto when temperature hits the threshold (with a menu-bar warning); the root helper reverts the fan to Auto if the app crashes or stops sending heartbeats — and on its own startup.

## Requirements

- Apple Silicon Mac with a fan (developed/verified on **MacBook Pro 14" M2 Pro**, macOS 26).
- Xcode toolchain (Swift 6.x). No third-party dependencies.

> Reading sensors needs no privileges. **Controlling the fan writes to the SMC, which requires root**, so fan control runs through a small privileged LaunchDaemon (installed once). Reading-only works without it.

## Install

```bash
git clone https://github.com/kurovu146/kurovitals.git
cd kurovitals
./scripts/build-release.sh        # build
./scripts/install-helper.sh       # install the root fan-control daemon (asks for sudo)
swift run KuroVitals              # run — four numbers appear in the menu bar
```

To start automatically at login:

```bash
./scripts/install-app.sh
```

To remove the helper:

```bash
./scripts/uninstall-helper.sh
```

## Architecture

Two processes, split by privilege:

```
┌─────────────────────────┐      Unix socket (JSON)       ┌──────────────────────┐
│  KuroVitals.app (user)  │ ──── set fan = 3000 rpm ─────▶ │ kurovitals-helper    │
│  • NSStatusItem render  │ ◀─── ok / state ──────────────│  (root LaunchDaemon) │
│  • CPU%/RAM via Mach     │                               │  • writes SMC F*Md/Tg │
│  • temp/fan via SMC (RO) │                               │  • TTL watchdog       │
└─────────────────────────┘                               └──────────────────────┘
```

Swift Package Manager modules:

| Module | Responsibility |
|---|---|
| `SMCKit` | IOKit `AppleSMC` read/write, typed value decoding (`flt`/`fpe2`/`ui8`/…) |
| `SystemStats` | CPU load (`host_statistics`), memory (`vm_statistics64`) |
| `SensorReader` | Combines temp (avg of `Tp*`+`Te*`) / CPU / RAM / fan into a `Snapshot` |
| `FanControl` | RPM clamp + over-temp auto-revert + heartbeat; Unix-socket `HelperClient` |
| `HelperProtocol` | Shared `Codable` command/response + socket path |
| `KuroVitals` | AppKit menu bar UI, `AppDelegate`, settings |
| `kurovitals-helper` | Root daemon: applies fan writes, TTL watchdog |

See `docs/superpowers/specs/` (design) and `docs/superpowers/spike-findings.md` (real M2 Pro SMC keys & verification).

## Development

```bash
swift build      # build all targets
swift test       # 19 unit tests (decoders, stats math, fan logic, formatter)
```

Diagnostics (read SMC keys; the `--test-high` mode requires sudo and spins the fan up to verify control):

```bash
swift run smc-dump                       # dump fan/temp keys
sudo .build/debug/smc-dump --test-high   # force ~5500 rpm and read back actual RPM
sudo .build/debug/smc-dump --revert      # safety: force fans back to Auto
```

## Notes

Fan control is unsupported by Apple and reverse-engineered via SMC keys. It was empirically verified on the target M2 Pro (actual RPM climbed to the requested target). Use at your own risk; firmware thermal throttling remains the ultimate hardware protection.
