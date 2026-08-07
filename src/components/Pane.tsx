import type { ReactNode } from "react";

interface PaneProps {
  label: string;
  children: ReactNode;
  /** Extra controls on the header rule, e.g. the pronunciation button. */
  action?: ReactNode;
}

/**
 * One labelled section of the popup.
 *
 * The body scrolls rather than clipping. This is the GUI form of the rule
 * inherited from `tl`: content is never silently dropped. There, a global line
 * cap quietly ate the Vietnamese pane and took five rounds to fully fix; here
 * the equivalent failure would be `overflow: hidden` on a long definition.
 */
export function Pane({ label, children, action }: PaneProps) {
  return (
    <section className="flex min-h-0 flex-col">
      <header className="flex shrink-0 items-center gap-2 px-3 pt-2 pb-1">
        <span className="text-[10px] font-semibold tracking-widest text-sky-700 uppercase dark:text-sky-400">
          {label}
        </span>
        <span
          aria-hidden
          className="h-px flex-1 bg-neutral-200 dark:bg-neutral-700"
        />
        {action}
      </header>
      <div className="min-h-0 overflow-y-auto px-3 pb-2 text-sm text-neutral-800 dark:text-neutral-100">
        {children}
      </div>
    </section>
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
