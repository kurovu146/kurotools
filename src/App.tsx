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

  useSystemTheme();
  const contentRef = useHeightFitsContent<HTMLDivElement>();

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
  // whatever the user last clicked. The picker stops Escape reaching this
  // while it is open, so the first press closes the picker and the second
  // closes the popup.
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") void hidePopup();
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

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
      <div ref={contentRef}>
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
      {picking && config && (
        <LanguagePicker
          selected={
            picking === "source" ? (config.source ?? AUTO) : config.target
          }
          includeAuto={picking === "source"}
          onPick={(code) => void pick(picking, code)}
          onDismiss={() => setPicking(null)}
        />
      )}
    </main>
  );
}
