import { useCallback, useEffect, useState } from "react";
import { hidePopup, onCapture } from "./capture";
import { LanguagePicker } from "./components/LanguagePicker";
import { LookupView } from "./components/LookupView";
import { Muted } from "./components/primitives";
import { PermissionGate } from "./components/PermissionGate";
import { AUTO, langConfig, setLangConfig, type LangConfig } from "./lang";
import { lookup, type Lookup } from "./lookup";
import { startWindowDrag, useHeightFitsContent, useSystemTheme } from "./window";

type State =
  | { kind: "idle" }
  | { kind: "loading"; text: string }
  | { kind: "done"; result: Lookup }
  | { kind: "needsPermission" };

export default function App() {
  const [state, setState] = useState<State>({ kind: "idle" });
  const [query, setQuery] = useState("");
  const [config, setConfig] = useState<LangConfig | null>(null);
  const [picking, setPicking] = useState<"source" | "target" | null>(null);
  /** The text the current result came from, so a language change can re-run it. */
  const [lastText, setLastText] = useState("");

  /**
   * The picker is really on screen — not merely requested.
   *
   * One name for all three things that have to agree: the overlay, the window
   * height, and `inert`. `config` is null until its IPC resolves and stays
   * null forever if that read failed, while the pair label keeps rendering
   * (it draws from the result, not the config) — so a click on it can ask to
   * pick with no picker to show. Keying the height off `picking` alone gave a
   * 520px panel empty below the result; keying `inert` off it would have been
   * worse, freezing the content behind an overlay that never appeared. Escape
   * reads it too, so a press is never swallowed closing something invisible.
   */
  const pickerOpen = picking !== null && config !== null;

  useSystemTheme();
  // The picker is an overlay outside the measured element, so it cannot size
  // the window itself; hold the panel open at full height while it is up.
  const contentRef = useHeightFitsContent<HTMLDivElement>(pickerOpen);

  useEffect(() => {
    // Only the pair label needs this, and it renders "Auto" until it arrives —
    // a failed read must not stop the panel showing a lookup.
    void langConfig().then(setConfig).catch(() => {});
  }, []);

  const run = useCallback(async (text: string) => {
    const trimmed = text.trim();
    if (!trimmed) {
      setState({ kind: "idle" });
      return;
    }
    setLastText(trimmed);

    setState({ kind: "loading", text: trimmed });
    // `lookup` cannot reject — the Rust side turns every failure into an
    // "unavailable" result — so there is deliberately no catch here.
    setState({ kind: "done", result: await lookup(trimmed) });
  }, []);

  // The hotkey path: the shell captures the selection and emits it.
  useEffect(() => {
    const unlisten = onCapture((event) => {
      // A new capture replaces everything on screen, and the popup may well
      // have been hidden with the picker still up — clicking away leaves no
      // event to close it. Left alone it would reappear over the new result,
      // at full height, listing languages for the lookup before it.
      setPicking(null);

      switch (event.kind) {
        case "text":
          setQuery(event.text);
          void run(event.text);
          break;
        case "needsPermission":
          setState({ kind: "needsPermission" });
          break;
        case "empty":
          setState({ kind: "idle" });
          setQuery("");
          break;
      }
    });
    return () => {
      void unlisten.then((f) => f());
    };
  }, [run]);

  /**
   * Change one side of the pair and look the same text up again.
   *
   * Re-runs on the text already in hand rather than re-capturing: the
   * selection that produced this result is long gone from the other app, and
   * asking for it again would be a different lookup.
   */
  const pick = useCallback(
    async (side: "source" | "target", code: string) => {
      setPicking(null);
      if (!config) return;

      const next =
        side === "source"
          ? { ...config, source: code === AUTO ? null : code }
          : { ...config, target: code };

      // Render what the backend actually stored — it repairs colliding
      // languages, so an optimistic local update can disagree with it.
      const stored = await setLangConfig(next).catch(() => null);
      if (!stored) return;
      setConfig(stored);
      if (lastText) void run(lastText);
    },
    [config, lastText, run],
  );

  // Esc dismisses. Bound to the window rather than an element so it works
  // whatever the user last clicked.
  //
  // The picker is peeled off here rather than by a handler inside it: that
  // overlay has no focus trap, and it renders after the content in DOM order,
  // so a single Shift+Tab lands focus on the buttons behind it. Any handler
  // scoped to the overlay's subtree would stop firing at that point and the
  // next Escape would take the whole popup with the picker still on screen.
  // Deciding from state holds wherever focus is — and from `pickerOpen`, not
  // `picking`, so a press cannot be swallowed closing something invisible.
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if (e.key !== "Escape") return;
      if (pickerOpen) {
        setPicking(null);
        return;
      }
      void hidePopup();
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [pickerOpen]);

  // The search box only appears when there is nothing to read. The system
  // panel has no input at all, and once a result is on screen the field is
  // just a bright bar sitting above the thing you actually wanted.
  const showInput = state.kind === "idle";

  return (
    // No tint over the vibrancy here — the translucent scrim is painted on
    // #root, under the rounded clip, so it covers the corners too. A
    // background on an inner element paints over the blur *and* squares off
    // the corners, which is exactly how the first attempt looked.
    //
    // The scroll lives on <main> while the height is measured from the child:
    // measuring a scroll container reports the height it already has, so the
    // panel could grow but never shrink.
    <main className="max-h-screen overflow-y-auto" onMouseDown={startWindowDrag}>
      {/* inert while the picker is up: the overlay is a sibling, not a modal
          dialog, so without this Shift+Tab walks focus onto the buttons
          underneath it — invisible below the scrim, and Enter there would
          speak or save a word from behind the picker. One attribute does what
          a focus trap would, and takes the content out of the a11y tree with
          it. */}
      <div ref={contentRef} inert={pickerOpen}>
        {state.kind === "needsPermission" && (
          <PermissionGate
            onGranted={() => setState({ kind: "idle" })}
            onSkip={() => setState({ kind: "idle" })}
          />
        )}

        {showInput && (
          <form
            className="px-3.5 pt-3.5"
            onSubmit={(e) => {
              e.preventDefault();
              void run(query);
            }}
          >
            <input
              autoFocus
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Look up a word…"
              aria-label="Text to look up"
              className="w-full rounded-lg bg-hover px-2.5 py-1.5 font-sans text-[13px] outline-none placeholder:text-fg-faint"
            />
          </form>
        )}

        {state.kind === "idle" && (
          <div className="px-3.5 pt-2 pb-3.5">
            <Muted>Select text anywhere, then press the hotkey.</Muted>
          </div>
        )}
        {state.kind === "loading" && (
          <div className="px-3.5 py-3.5">
            <Muted>Looking up “{state.text}”…</Muted>
          </div>
        )}
        {state.kind === "done" && (
          <LookupView
            result={state.result}
            // Italic marks a guess, so it tracks the *configuration*: a null
            // source means the code on screen came from detection. The result
            // alone cannot say — `source_lang` holds the configured language
            // and the detected one alike.
            sourceDetected={
              config?.source === null && state.result.source_lang !== null
            }
            onPickSource={() => setPicking("source")}
            onPickTarget={() => setPicking("target")}
          />
        )}
      </div>

      {/* Outside the measured <div> on purpose: a list inside it would grow
          the window every time the picker opened. */}
      {pickerOpen && (
        <LanguagePicker
          selected={
            picking === "source" ? (config.source ?? AUTO) : config.target
          }
          includeAuto={picking === "source"}
          onPick={(code) => void pick(picking, code)}
        />
      )}
    </main>
  );
}
