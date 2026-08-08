import type { Lookup } from "../lookup";
import { Divider, Headword, Label, Muted, Sense } from "./primitives";
import { SourceActions } from "./SourceActions";

const MAX_CHARS = 5000;

/**
 * The result, laid out like the macOS Look Up panel: the looked-up text at the
 * top with its senses beneath, a hairline, then the Vietnamese translation.
 *
 * Two rules carried over from `tl`, both load-bearing:
 *
 * - The dictionary senses are **omitted entirely** when there are none. An
 *   empty labelled block is noise, not information.
 * - The translation **always renders**, showing "unavailable" when there is
 *   none. It is the block the tool exists for, so its absence must be stated
 *   rather than inferred from a gap.
 */
export function LookupView({ result }: { result: Lookup }) {
  const partsOfSpeech = partOfSpeechLine(result.definitions);

  return (
    <div className="px-3.5 pt-3 pb-3.5">
      {/* items-start, not items-center: against a two-line phrase the buttons
          belong beside the first line, not floating at its midpoint. */}
      <div className="flex items-start gap-2">
        <Headword text={result.source} />
        <SourceActions text={result.source} />
      </div>

      {partsOfSpeech && (
        <p className="pt-1 text-[12px] text-fg-dim italic">{partsOfSpeech}</p>
      )}

      {result.definitions.length > 0 && (
        <ol className="pt-1.5">
          {result.definitions.map((d, i) => (
            <Sense key={i} index={i + 1}>
              {d.domain && <span className="text-fg-dim italic">{d.domain} </span>}
              {d.gloss}
            </Sense>
          ))}
        </ol>
      )}

      {result.source_truncated && (
        <p className="pt-1.5 text-[12px] text-fg-faint italic">
          … truncated at {MAX_CHARS.toLocaleString()} characters — only that
          much was sent
        </p>
      )}

      <Divider />

      <Label>Vietnamese</Label>
      {result.translation ? (
        <p className="text-[14px] leading-snug break-words whitespace-pre-wrap">
          {result.translation}
        </p>
      ) : (
        <Muted>unavailable</Muted>
      )}
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
