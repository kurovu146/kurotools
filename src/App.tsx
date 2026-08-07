import { useCallback, useEffect, useState } from "react";
import { hidePopup, onCapture } from "./capture";
import { LookupView } from "./components/LookupView";
import { Muted } from "./components/Section";
import { PermissionGate } from "./components/PermissionGate";
import { lookup, type Lookup } from "./lookup";
import { useHeightFitsContent, useSystemTheme } from "./window";

type State =
  | { kind: "idle" }
  | { kind: "loading"; text: string }
  | { kind: "done"; result: Lookup }
  | { kind: "needsPermission" };

export default function App() {
  const [state, setState] = useState<State>({ kind: "idle" });
  const [query, setQuery] = useState("");

  useSystemTheme();
  const contentRef = useHeightFitsContent<HTMLDivElement>();

  const run = useCallback(async (text: string) => {
    const trimmed = text.trim();
    if (!trimmed) {
      setState({ kind: "idle" });
      return;
    }

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

  // Esc dismisses. Bound to the window rather than an element so it works
  // whatever the user last clicked.
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") void hidePopup();
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  if (state.kind === "needsPermission") {
    return (
      <main
        ref={contentRef}
        className="bg-neutral-200/60 text-neutral-900 dark:bg-neutral-800/40 dark:text-neutral-50"
      >
        <PermissionGate
          onGranted={() => setState({ kind: "idle" })}
          onSkip={() => setState({ kind: "idle" })}
        />
      </main>
    );
  }

  // The search box only appears when there is nothing to read. The system
  // panel has no input at all, and once a result is on screen the field is
  // just a bright bar sitting above the thing you actually wanted.
  const showInput = state.kind === "idle";

  return (
    // No tint over the vibrancy — a background here paints over the blur and
    // turns the panel into a flat slab, which is exactly how the first attempt
    // looked. Only the text colours are set.
    <main
      ref={contentRef}
      className="text-neutral-900 dark:text-neutral-100"
    >
      {showInput && (
        <form
          className="px-4 pt-4"
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
            className="w-full rounded-lg bg-black/5 px-3 py-1.5 font-sans text-[13px] outline-none placeholder:text-neutral-500 focus:bg-black/10 dark:bg-white/10 dark:placeholder:text-neutral-400 dark:focus:bg-white/15"
          />
        </form>
      )}

      {state.kind === "idle" && (
        <div className="px-4 pt-2 pb-4">
          <Muted>Select text anywhere, then press the hotkey.</Muted>
        </div>
      )}
      {state.kind === "loading" && (
        <div className="p-4">
          <Muted>Looking up “{state.text}”…</Muted>
        </div>
      )}
      {state.kind === "done" && <LookupView result={state.result} />}
    </main>
  );
}
