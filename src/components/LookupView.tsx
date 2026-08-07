import type { Lookup } from "../lookup";
import { Headword, Muted, Section, Sense } from "./Section";
import { SourceActions } from "./SourceActions";

const MAX_CHARS = 5000;

/**
 * The result, laid out like the macOS Look Up panel: an **English** section
 * with the headword and numbered senses, then a **Vietnamese** section.
 *
 * Two rules carried over from `tl`, both load-bearing:
 *
 * - The English section is **omitted entirely** when there are no definitions.
 *   An empty labelled section is noise, not information.
 * - The Vietnamese section **always renders**, showing "unavailable" when there
 *   is no translation. It is the section the tool exists for, so its absence
 *   must be stated rather than inferred from a gap.
 */
export function LookupView({ result }: { result: Lookup }) {
  const hasDefinitions = result.definitions.length > 0;

  return (
    <div className="flex h-full min-h-0 flex-col overflow-y-auto pb-3">
      {hasDefinitions ? (
        <Section label="English" action={<SourceActions text={result.source} />}>
          <Headword
            word={result.source}
            detail={partOfSpeechLine(result.definitions)}
          />
          {result.definitions.map((d, i) => (
            <Sense key={i} index={i + 1}>
              {d.domain && (
                <span className="text-neutral-600 italic dark:text-neutral-400">
                  {d.domain}{" "}
                </span>
              )}
              {d.gloss}
            </Sense>
          ))}
        </Section>
      ) : (
        /* No dictionary entry — a phrase, or a word the endpoint does not know.
           The source still needs showing, since it is what was actually sent. */
        <Section label="Source" action={<SourceActions text={result.source} />}>
          <p className="break-words whitespace-pre-wrap">{result.source}</p>
        </Section>
      )}

      {result.source_truncated && (
        <div className="px-4">
          <Muted>
            … truncated at {MAX_CHARS.toLocaleString()} characters — only that
            much was sent
          </Muted>
        </div>
      )}

      <Section label="Vietnamese">
        {result.translation ? (
          <p className="break-words whitespace-pre-wrap">{result.translation}</p>
        ) : (
          <Muted>unavailable</Muted>
        )}
      </Section>
    </div>
  );
}

/**
 * The parts of speech present, joined — "noun · verb".
 *
 * Deduplicated because the endpoint repeats the part of speech on every sense
 * within a group, so a raw join reads "noun · noun · verb".
 */
function partOfSpeechLine(definitions: Lookup["definitions"]): string {
  const seen: string[] = [];
  for (const d of definitions) {
    if (d.part_of_speech && !seen.includes(d.part_of_speech)) {
      seen.push(d.part_of_speech);
    }
  }
  return seen.join(" · ");
}
