# SMC Spike Findings — MacBook Pro M2 Pro (macOS 26.5.1)

**Date:** 2026-06-27  
**Machine:** MacBook Pro M2 Pro (Apple Silicon)  
**Task:** SPIKE — dump real SMC keys and record layout for Tasks 5 & 8

---

## Bug Found & Fixed: Swift struct layout ≠ C struct layout

**Root cause of initial `kIOReturnBadArgument` (-536870206):**  
Swift's struct layout algorithm does NOT add trailing padding to an embedded struct when the
parent struct contains further fields. In `SMCKeyInfoData` (dataSize:u32 + dataType:u32 +
dataAttributes:u8 = 9 bytes), Swift used size=9 rather than the C-padded stride=12.
This shifted every downstream field by 4 bytes:

| Field    | Swift offset | C offset (expected) |
|----------|-------------|---------------------|
| result   | 37          | 40                  |
| data32   | 40          | 44                  |
| bytes[0] | 44          | 48                  |
| total    | 76 bytes    | 80 bytes            |

**Fix applied (in `Sources/SMCKit/SMCConnection.swift`):**  
Added `var _pad: (UInt8, UInt8, UInt8) = (0, 0, 0)` inside `SMCKeyInfoData` to force the
Swift stride to 12, matching C. Struct total is now 80 bytes with correct field offsets.

---

## Read Permission Result

**Reads succeeded as a normal user with NO sudo.** ✓  
`IOServiceOpen("AppleSMC")` and all `IOConnectCallStructMethod` calls work without elevated
privileges on Apple Silicon. The GUI app will NOT need a privileged helper for SMC reads.
(Fan writes still require the helper — that is Task 5.)

---

## Total Key Count

**2299 SMC keys** on this M2 Pro.

---

## Fan Keys

`FNum` = **2** (two fans confirmed — M2 Pro MBP has left + right fans).

| Key  | Type | Value (sample) | Description               |
|------|------|---------------|---------------------------|
| FNum | ui8  | 2             | Fan count                 |
| F0Ac | flt  | 2320.96 RPM   | Fan 0 actual speed        |
| F0Mn | flt  | 2317.00 RPM   | Fan 0 minimum speed       |
| F0Mx | flt  | 6800.00 RPM   | Fan 0 maximum speed       |
| F0Md | ui8  | 0             | Fan 0 mode (0=auto)       |
| F0Tg | flt  | 2317.00 RPM   | Fan 0 target speed        |
| F0Dc | flt  | 0.193         | Fan 0 duty cycle (0–1)    |
| F0St | ui8  | 5             | Fan 0 status              |
| F0Sf | ui16 | 0             | Fan 0 safety flag         |
| F0Fb | ui8  | 1             | Fan 0 feedback enabled    |
| F0Fc | ui16 | 4             | Fan 0 config              |
| F1Ac | flt  | 2526.26 RPM   | Fan 1 actual speed        |
| F1Mn | flt  | 2317.00 RPM   | Fan 1 minimum speed       |
| F1Mx | flt  | 6800.00 RPM   | Fan 1 maximum speed       |
| F1Md | ui8  | 0             | Fan 1 mode (0=auto)       |
| F1Tg | flt  | 2502.00 RPM   | Fan 1 target speed        |
| F1Dc | flt  | 0.205         | Fan 1 duty cycle (0–1)    |
| FOff | ui8  | 1             | Fan-off capability flag   |

### Key surprise: F0Tg / F1Tg are type `flt ` (IEEE 754 float), NOT `fpe2`

On Intel Macs, fan target keys used `fpe2` (fixed-point, 2 fractional bits). On M2 Pro they
use `flt` (4-byte IEEE 754). Task 5 must write 4-byte little-endian float when setting
`F0Tg` / `F1Tg`. The `writeKey` selector and `flt` encoding must be used.

---

## Temperature Keys

### Tc* (CPU) — NONE on M2 Pro

Zero keys with prefix `Tc`. The classic Intel keys (`TC0P`, `TC0D`, `TC0E`) do not exist on
Apple Silicon. Task 8 must NOT look for `Tc*` keys.

### Tp* (P-core temps) — 54 keys, all `flt`, values 51–76 °C

All keys are plausible CPU temperatures (0 < v < 120). These are individual P-core die
temperature sensors. Sample values at idle/light load:

| Key  | Value  | Key  | Value  |
|------|--------|------|--------|
| Tp00 | 62.9°C | Tp0A | 75.7°C |
| Tp01 | 69.6°C | Tp0C | 58.7°C |
| Tp02 | 75.8°C | Tp0D | 63.3°C |
| Tp04 | 59.6°C | Tp0E | 67.5°C |
| Tp05 | 64.3°C | Tp16 | 53.0°C |
| Tp06 | 68.0°C | Tp1C | 75.5°C |
| ... (54 total Tp keys) ...      |        |

### Te* (E-core temps) — 3 keys, all `flt`, values 50–59 °C

| Key  | Value  | Description     |
|------|--------|-----------------|
| Te04 | 50.6°C | E-core cluster  |
| Te05 | 56.7°C | E-core cluster  |
| Te06 | 59.2°C | E-core cluster  |

### Tg* (GPU temps) — 10 keys, mostly zero or ~5–6 °C

Values 0.000 or 5.7°C are suspiciously low. GPU appears idle/near-ambient. Not recommended
for "CPU temp" averaging. May represent GPU cluster sensors with power-gated domains.

---

## Recommendation for Task 8 (CPU temp averaging)

**Use all `Tp*` keys** (54 P-core sensors) **plus all `Te*` keys** (3 E-core sensors) for a
comprehensive CPU temperature:

```
cpuTemp = mean(allTp + allTe)
```

- All values are `flt` type — same decode path.
- Range at idle: ~51–76°C (center ~62°C). Plausible for M2 Pro under light load.
- Skip `Tc*` (absent), skip `Tg*` (low/zero values indicate GPU idle, not CPU).

For a simpler single "hot spot" value (optional), use `max(allTp)` which reliably tracks
the hottest P-core cluster.

---

## Other Notes

- `FOFC` (ui32, value 5553): total fan RPM sum — may be useful for quick sanity-check.
- `FRmp` (ui16, value 0): fan ramp flag.
- `FBAD` (type=????, unknown): SMCKit reports `.unknown` data type; read returns 0. Not used.
- `FOff` = 1: fans CAN spin down to zero (fan-off feature) — relevant for Task 5 min-speed logic.
- All fan speed values (Ac, Mn, Mx, Tg) are `flt` on M2 Pro (vs `fpe2` on Intel).

---

## Fan Write Verification — ✅ CONFIRMED WORKING (2026-06-27)

The write path (Task 5: `SMC.write`, `setFanMode`, `setFanTarget` — both fans F0 and F1) was
verified on the real M2 Pro by a human running `sudo .build/debug/smc-dump --test-high`, which
forces a high target (5500 RPM) and reads back **actual** fan RPM each second.

**Result: fan control WORKS.** Actual `F0Ac` climbed from ~2400 RPM toward the 5500 target
(observed: t=1s 2400 → t=2s 3200 → … → 5500), then returned to Auto on revert. The firmware
HONORS SMC fan writes on this machine — the GUI control path (helper daemon + RPM UI) is viable.

Notes:
- The initial `--test-write` (target = F0Mn+200 ≈ 2517 RPM) was inaudible/ambiguous because it
  barely exceeded the idle speed; the `--test-high` empirical readback is the reliable check.
- Root IS required for writes (writes from a normal-user process fail); confirms the
  privileged-helper architecture (Tasks 10–12).

Safety fallback if a future test is interrupted mid-run:
```bash
sudo .build/debug/smc-dump --revert
```
