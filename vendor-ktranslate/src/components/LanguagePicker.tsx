import { useEffect, useMemo, useRef, useState } from "react";
import { AUTO, languageName, languages, recentLanguages } from "../lang";

/**
 * A full-panel overlay listing every language, filtered as you type.
 *
 * `fixed` rather than inline on purpose: the window sizes itself to a measured
 * inner element (see useHeightFitsContent), so a list in the normal flow would
 * grow the panel every time the picker opened and it would never shrink back.
 * The overlay is rendered as a sibling of that measured element, never a child;
 * the window is held at full height while it is open instead.
 *
 * Dismissal is App's job, not a prop here: Escape has to work from wherever
 * focus is, including behind this overlay, so the only handler is the
 * window-level one.
 */
export function LanguagePicker({
  selected,
  includeAuto,
  onPick,
}: {
  selected: string;
  /** Only the source side offers auto-detect. */
  includeAuto: boolean;
  onPick: (code: string) => void;
}) {
  const [all, setAll] = useState<string[]>([]);
  const [recents, setRecents] = useState<string[]>([]);
  const [filter, setFilter] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    // Names are cosmetic and the list is static — a failed load leaves an
    // empty picker, which is still dismissable, rather than a broken panel.
    void languages().then(setAll).catch(() => {});
    void recentLanguages().then(setRecents).catch(() => {});
    inputRef.current?.focus();
  }, []);

  const ordered = useMemo(() => {
    const head = includeAuto ? [AUTO] : [];
    // Recents first, then everything else alphabetically by display name.
    const rest = all
      .filter((c) => !recents.includes(c))
      .sort((a, b) => languageName(a).localeCompare(languageName(b)));
    return [...head, ...recents.filter((c) => all.includes(c)), ...rest];
  }, [all, recents, includeAuto]);

  const shown = useMemo(() => {
    const needle = filter.trim().toLowerCase();
    if (!needle) return ordered;
    return ordered.filter(
      (c) =>
        languageName(c).toLowerCase().includes(needle) ||
        c.toLowerCase().includes(needle),
    );
  }, [ordered, filter]);

  return (
    <div
      className="fixed inset-0 z-10 flex flex-col bg-scrim"
      // The panel drags from anywhere; the picker must not move the window.
      // Escape is deliberately *not* handled here: this overlay has no focus
      // trap, so one Shift+Tab puts focus on the buttons behind it and any
      // handler scoped to this subtree stops firing. App decides it instead,
      // from `picking`, which holds wherever focus happens to be.
      onMouseDown={(e) => e.stopPropagation()}
    >
      <input
        ref={inputRef}
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
        // Enter is bound to the field alone: on a focused list button the
        // browser already turns Enter into a click, and a second handler here
        // would pick the top match on top of the one actually chosen.
        onKeyDown={(e) => {
          if (e.key === "Enter" && shown.length > 0) onPick(shown[0]);
        }}
        placeholder="Search languages…"
        aria-label="Search languages"
        className="m-2 shrink-0 rounded-lg bg-hover px-2.5 py-1.5 font-sans text-[13px] outline-none placeholder:text-fg-faint"
      />

      <ul className="min-h-0 flex-1 overflow-y-auto pb-2">
        {shown.map((code) => (
          <li key={code}>
            <button
              onClick={() => onPick(code)}
              aria-current={code === selected}
              // focus-visible mirrors hover rather than drawing a ring: it is
              // the highlight this panel already uses to say "this row", and
              // without it tabbing through the list moves nothing visible.
              className={`flex w-full items-baseline gap-2 px-3.5 py-1 text-left text-[13px] hover:bg-hover focus-visible:bg-hover ${
                code === selected ? "font-medium text-fg" : "text-fg-dim"
              }`}
            >
              <span className="min-w-0 truncate">{languageName(code)}</span>
              <span className="shrink-0 text-[11px] text-fg-faint">{code}</span>
            </button>
          </li>
        ))}
        {shown.length === 0 && (
          <li className="px-3.5 py-2 text-[13px] text-fg-faint italic">
            No match
          </li>
        )}
      </ul>
    </div>
  );
}
