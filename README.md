# Tra

Look up any word you select, without leaving what you are reading.

Select text in any application, press the hotkey, and a small popup shows three
things: the text you selected, its **English definition**, and its **Vietnamese
translation**.

> **`tra` is a working codename**, not the final product name.

## Why two panes instead of one

Google Translate is unreliable on technical English, and you cannot tell a bad
translation from a good one without already knowing the word. Measured against
the live endpoint while building this:

| English | Google's Vietnamese | What it actually means |
|---|---|---|
| `idempotent` | bình thường (*normal*) | unchanged when applied repeatedly |
| `race condition` | điều kiện cuộc đua (*a racing competition*) | two threads touching shared state |
| `staging` | dàn dựng (*theatre staging*) | the environment before production |

Five of seven sampled technical terms came back wrong. The English definition
pane is the check: when it reads "producing the same result when applied
repeatedly" and the translation reads "bình thường", the mismatch is visible.

That pane is free and always will be. It is the reason to use this over a
browser tab.

## Requirements

- **macOS** 10.15+ — needs Accessibility permission (see below)
- **Windows** 10+ — needs the WebView2 runtime, preinstalled on Windows 11
- **Linux** — needs `libwebkit2gtk`; optionally `spd-say` or `espeak` for
  pronunciation

## Usage

| | |
|---|---|
| **Hotkey** | `Cmd+Shift+D` on macOS, `Ctrl+Shift+D` elsewhere |
| **Dismiss** | `Esc`, or click away |
| **Tray icon** | Show, and Quit |
| **Also** | type directly into the popup's search box |

Press `★` to save a word, `►` to hear it pronounced by the system voice.

## macOS: the Accessibility permission

Reading the text you have selected in *another* application is not something
macOS lets an app do directly. Tra does what every tool in this category does:
it synthesizes `Cmd+C`, reads the clipboard, and **puts your clipboard back
exactly as it was**. That requires Accessibility access.

The first launch explains this and opens System Settings to the right pane. The
grant is detected without restarting the app.

**Declining is fine.** Tra still works — copy the text first, then press the
hotkey. That path needs no permission at all.

## macOS: native fullscreen apps

**Known limitation.** The popup does not appear over an app in *native*
fullscreen — the green-button kind that macOS gives its own Space. Everywhere
else it works, including ordinary Spaces and maximised windows.

If you work in a fullscreen terminal, one line of Ghostty config fixes it:

```
macos-non-native-fullscreen = true
```

Ghostty then fills the screen without claiming its own Space, and the popup
appears over it normally. tmux `zoom` and a maximised window are unaffected
either way.

<details>
<summary>What was tried</summary>

Each of these was verified as actually applied, and none was sufficient:

| Attempt | Outcome |
|---|---|
| `CanJoinAllSpaces \| FullScreenAuxiliary` (reads back `257`) | no effect |
| Window level raised from 5 to 101 | no effect |
| Applied once at startup rather than per-show | no effect |
| `orderFrontRegardless()` | no effect |
| `ActivationPolicy::Regular` instead of `Accessory` | no effect |

Only the collection-behaviour flags were kept, since they are the documented
mechanism for ordinary Spaces; the rest were reverted as unproven.

The untried difference from launcher utilities that manage this (Raycast,
Alfred) is that they use an `NSPanel` with `.nonactivatingPanel`, while Tauri
creates an `NSWindow`. That cannot be changed at runtime — it needs Tauri's
window construction patched.

Applying the flags inside `show` fails silently two ways, worth knowing if this
is revisited: `run_on_main_thread` is asynchronous, so the change lands after
the window is placed, and `set_visible_on_all_workspaces` is itself a
`setCollectionBehavior` call carrying only `CanJoinAllSpaces`, which wipes the
fullscreen flag every time.

</details>

For single English words on macOS there is also **`⌃⌘D`** — the built-in Look
Up panel, which includes a Vietnamese–English dictionary and works over
fullscreen, because it is drawn by the app that owns the text rather than being
a separate window.

## Inside tmux, copy first

Select-then-hotkey **does not work inside a terminal multiplexer**, and cannot
be made to. With `mouse on`, dragging creates a *tmux* selection; tmux owns it
internally and only hands it to the system clipboard when you press your copy
binding. The synthesized ⌘C reaches the terminal emulator, which has no
selection of its own, so nothing is copied.

In tmux, use your normal copy key first — with the common vi-mode binding
that's `y` — then press the hotkey. Tra reads the clipboard and works exactly
as usual.

Everywhere else (browsers, PDFs, editors, chat apps) select-then-hotkey works;
measured at ~100ms.

## Linux: Wayland

Global shortcuts on Wayland depend on your compositor implementing the XDG
`GlobalShortcuts` portal, and not all do. If the hotkey never fires, bind this
in your compositor's own config instead:

```
tra --show
```

That summons the popup on the already-running instance and behaves identically.

On **X11** everything works out of the box, and better than elsewhere: selecting
text already fills the PRIMARY selection, so nothing is synthesized and your
clipboard is never touched.

On **GNOME/Wayland** specifically, PRIMARY cannot be read (no
`wlr-data-control`), so Tra falls back to the clipboard — copy first.

## Development

```bash
bun install
bun run tauri dev          # run
cargo test                 # 47 tests, fully offline
cargo test -- --ignored    # the one test that hits the live Google endpoint
bun run tauri build        # bundle
```

### Layout

```
crates/tra-core/   pure Rust: capture, providers, model, storage, TTS.
                   Must never depend on tauri — enforced by a test.
src-tauri/         the Tauri shell: window, tray, hotkey, IPC.
src/               React + Tailwind frontend.
```

The core is framework-free on purpose. It keeps the logic testable without a
GUI harness, and it means replacing the desktop shell would cost the shell
rather than the app.

### Verify the riskiest part on its own

```bash
cargo run -p tra-core --example capture_spike
```

Select text in another application during the countdown. It reports what it
captured and, importantly, whether your clipboard survived.

## Status

**v1, free core.** Verified end to end on macOS only.

**Windows and Linux compile but have not been run on real hardware.** Treat
them as unverified — a passing build on one platform routinely hides bugs on
another.

Not built yet: a settings screen (the hotkey and database path are currently
fixed), and the paid tier — AI translation, spaced repetition, OCR.
