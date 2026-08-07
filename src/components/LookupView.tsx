import type { Lookup } from "../lookup";
import { Muted, Pane } from "./Pane";

const MAX_CHARS = 5000;

/**
 * The three panes: source, English definition, Vietnamese translation.
 *
 * Two rules carried over from `tl`, both load-bearing:
 *
 * - The **EN pane is omitted entirely** when there are no definitions. An
 *   empty labelled pane is noise, not information.
 * - The **VI pane always renders**, showing "unavailable" when there is no
 *   translation. It is the pane the tool exists for, so its absence must be
 *   stated rather than inferred from a gap.
 */
export function LookupView({ result }: { result: Lookup }) {
  return (
    <div className="grid h-full min-h-0 grid-rows-[auto_auto_1fr] divide-y divide-neutral-200 dark:divide-neutral-700">
      <Pane label="source">
        <p className="break-words whitespace-pre-wrap">{result.source}</p>
        {result.source_truncated && (
          <Muted>
            … truncated at {MAX_CHARS.toLocaleString()} characters — only that
            much was sent
          </Muted>
        )}
      </Pane>

      {result.definitions.length > 0 && (
        <Pane label="EN">
          <ul className="space-y-2">
            {result.definitions.map((d, i) => (
              <li key={i}>
                <p className="text-[11px] text-neutral-500 dark:text-neutral-400">
                  {d.part_of_speech}
                  {d.domain && ` · ${d.domain}`}
                </p>
                <p className="break-words">{d.gloss}</p>
              </li>
            ))}
          </ul>
        </Pane>
      )}

      <Pane label="VI">
        {result.translation ? (
          <p className="break-words whitespace-pre-wrap">{result.translation}</p>
        ) : (
          <Muted>unavailable</Muted>
        )}
      </Pane>
    </div>
  );
}
