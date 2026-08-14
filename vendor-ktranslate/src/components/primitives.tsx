import type { ReactNode } from "react";

/**
 * Presentational pieces of the panel, styled after the macOS Look Up popup.
 *
 * The shape being copied: the looked-up text sits at the top as the largest
 * thing on screen, secondary detail is small and dimmed, and a single hairline
 * separates the dictionary entry from the translation. There are no boxes,
 * borders or headers with rules running across them — the earlier attempt had
 * those and it read as a web page in a window.
 */

/** Longer than this and the source is a phrase, not a headword. */
const HEADWORD_MAX_CHARS = 28;

/**
 * The text that was looked up.
 *
 * A single word gets the large display size the system panel uses. A whole
 * sentence at that size would fill the panel before the translation — the
 * thing actually wanted — got a line, so it drops to body size instead.
 */
export function Headword({ text }: { text: string }) {
  const isWord = text.length <= HEADWORD_MAX_CHARS && !text.includes("\n");

  return (
    <p
      className={
        isWord
          ? "min-w-0 flex-1 text-[21px] leading-tight font-semibold break-words"
          : "min-w-0 flex-1 text-[14px] leading-snug break-words whitespace-pre-wrap"
      }
    >
      {text}
    </p>
  );
}

/** Small sans label above a block — "Vietnamese". */
export function Label({ children }: { children: ReactNode }) {
  return (
    <h2 className="pb-1 font-sans text-[10px] font-medium tracking-[0.07em] text-fg-faint uppercase">
      {children}
    </h2>
  );
}

/**
 * A numbered sense.
 *
 * `tabular-nums` keeps the numerals a fixed width so the glosses of senses 1
 * through 10 all start on the same column.
 */
export function Sense({
  index,
  children,
}: {
  index: number;
  children: ReactNode;
}) {
  return (
    <li className="flex gap-2 pb-[3px] text-[13px] leading-snug">
      <span className="shrink-0 tabular-nums text-fg-faint">{index}</span>
      <span className="min-w-0 break-words">{children}</span>
    </li>
  );
}

/** Hairline between the entry and the translation. */
export function Divider() {
  return <div aria-hidden className="my-2.5 h-px bg-rule" />;
}

/** Dimmed secondary text — "unavailable", truncation notes, hints. */
export function Muted({ children }: { children: ReactNode }) {
  return <p className="text-[13px] text-fg-dim italic">{children}</p>;
}
