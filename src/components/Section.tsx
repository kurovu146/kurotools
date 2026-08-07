import type { ReactNode } from "react";

interface SectionProps {
  /** e.g. "English", "Vietnamese" — mirrors the system Look Up panel. */
  label: string;
  children: ReactNode;
  /** Extra controls aligned to the right of the header rule. */
  action?: ReactNode;
}

/**
 * One labelled section, styled after the macOS Look Up panel: a serif heading
 * with a hairline rule running to the right edge.
 *
 * The body scrolls rather than clipping. This is the GUI form of the rule
 * inherited from `tl`: content is never silently dropped — there a global line
 * cap quietly ate the Vietnamese pane, here the equivalent would be
 * `overflow: hidden` on a long definition.
 */
export function Section({ label, children, action }: SectionProps) {
  return (
    <section className="flex min-h-0 flex-col px-4">
      <header className="flex shrink-0 items-center gap-3 pt-3 pb-1.5">
        <h2 className="text-[15px] text-neutral-800 dark:text-neutral-200">
          {label}
        </h2>
        <span
          aria-hidden
          className="h-px flex-1 bg-neutral-400/40 dark:bg-neutral-400/25"
        />
        {action}
      </header>
      <div className="min-h-0 overflow-y-auto pb-1 text-[13px] text-neutral-900 dark:text-neutral-100">
        {children}
      </div>
    </section>
  );
}

/** The word being looked up — bold serif, as in the system panel. */
export function Headword({
  word,
  detail,
}: {
  word: string;
  detail?: ReactNode;
}) {
  return (
    <p className="flex flex-wrap items-baseline gap-2 pb-0.5">
      <span className="text-[17px] font-bold break-words">{word}</span>
      {detail && (
        <span className="text-[13px] text-neutral-600 italic dark:text-neutral-400">
          {detail}
        </span>
      )}
    </p>
  );
}

/**
 * A numbered sense, indented under its headword.
 *
 * `tabular-nums` keeps the numerals a fixed width so the glosses of senses 1
 * through 10 all start on the same column.
 */
export function Sense({ index, children }: { index: number; children: ReactNode }) {
  return (
    <p className="flex gap-2 pb-0.5 pl-1">
      <span className="shrink-0 tabular-nums text-neutral-500 dark:text-neutral-400">
        {index}
      </span>
      <span className="break-words">{children}</span>
    </p>
  );
}

/** Dimmed secondary text — "unavailable", truncation notes, hints. */
export function Muted({ children }: { children: ReactNode }) {
  return (
    <p className="text-[13px] text-neutral-500 italic dark:text-neutral-400">
      {children}
    </p>
  );
}
