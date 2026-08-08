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

### Which languages have definitions

The definition pane is filled from Google's dictionary data, which covers far
fewer languages than translation does. Measured: **English, Spanish, French,
German, Italian, Russian and Arabic** return definitions. Chinese, Japanese,
Korean, Vietnamese, Thai, Hindi and most others return none, and the pane is
hidden rather than shown empty.

Translation itself works for every language in the picker.

## Requirements

- **macOS** 10.15+ — needs Accessibility permission (see below)
- **Windows** 10+ — needs the WebView2 runtime, preinstalled on Windows 11
- **Linux** — needs `libwebkit2gtk`; optionally `spd-say` or `espeak` for
  pronunciation

## Usage

| | |
|---|---|
| **Hotkey** | `Cmd+Shift+D` on macOS, `Ctrl+Shift+D` elsewhere |
| **Dismiss** | press the hotkey again; `Esc` and click-away also work when the popup has focus |
| **Languages** | click either half of the `AUTO → VIETNAMESE` label under the entry |
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

Works. The popup appears over apps in native fullscreen — the green-button kind
macOS gives its own Space — and **does not move you off that Space**.

This costs keyboard focus, deliberately. Activating the app is what forces
macOS to leave a fullscreen Space, so the window is ordered in *without*
activating (`orderFrontRegardless`, with `CanJoinAllSpaces` and
`FullScreenAuxiliary`). A non-activating `NSWindow` receives no key events, so:

- **Esc does not dismiss.** Press the hotkey again — it toggles.
- **Typing into the search box does not work** while the popup is summoned by
  the hotkey. Select-then-hotkey is unaffected, which is the main flow.

Getting both fullscreen and keyboard needs an `NSPanel` with
`.nonactivatingPanel`. Tauri creates an `NSWindow`, and the two cannot be
swapped at runtime, so that would mean patching Tauri's window construction.

<details>
<summary>What did not work, and why</summary>

| Attempt | Outcome |
|---|---|
| `CanJoinAllSpaces \| FullScreenAuxiliary` alone | window stays on its own Space |
| Window level 5 → 101 | no effect |
| `ActivationPolicy::Regular` instead of `Accessory` | no effect |
| `MoveToActiveSpace` + `NSApp.activate` | appears, **but drags the user out of fullscreen** |

The last one is the trap: `MoveToActiveSpace` only fires on activation, and
activation is precisely what leaves the fullscreen Space. Appearing is not
enough if the user is yanked away from what they were reading.

Applying the flags inside `show` also fails silently two ways:
`run_on_main_thread` is asynchronous so the change lands after the window is
placed, and `set_visible_on_all_workspaces` is itself a `setCollectionBehavior`
call carrying only `CanJoinAllSpaces`, which overwrites whatever was set. They
are applied once in `setup`, which already runs on the main thread.

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
cargo test                 # 106 tests, fully offline
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
