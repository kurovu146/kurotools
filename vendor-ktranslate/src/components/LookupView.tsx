import { languageName } from "../lang";
import type { Lookup } from "../lookup";
import { Divider, Headword, Muted, Sense } from "./primitives";
import { SourceActions } from "./SourceActions";

const MAX_CHARS = 5000;

/**
 * The result, laid out like the macOS Look Up panel: the looked-up text at the
 * top with its senses beneath, a hairline, then the translation under the
 * language pair that produced it.
 *
 * Two rules carried over from `tl`, both load-bearing:
 *
 * - The dictionary senses are **omitted entirely** when there are none. An
 *   empty labelled block is noise, not information.
 * - The translation **always renders**, showing "unavailable" when there is
 *   none. It is the block the tool exists for, so its absence must be stated
 *   rather than inferred from a gap.
 */
export function LookupView({
  result,
  sourceDetected,
  onPickSource,
  onPickTarget,
}: {
  result: Lookup;
  /** The source language was guessed, not configured — see PairButton. */
  sourceDetected: boolean;
  onPickSource: () => void;
  onPickTarget: () => void;
}) {
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

      {/* data-selectable: the senses and the translation are the parts worth
          copying out, so they keep the pointer instead of dragging the window.
          The headword row above deliberately does not — it is the panel's
          handle, and its text is already selected in the app it came from. */}
      {result.definitions.length > 0 && (
        <ol className="pt-1.5" data-selectable>
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

      {/* The pair replaces what used to be a static "Vietnamese" label: the
          only chrome the picker needs already existed. `target_lang` is the
          language actually used, not the configured one — the no-op retry can
          land in the fallback, and the label has to follow it. */}
      <h2 className="flex items-baseline gap-1 pb-1 font-sans text-[10px] font-medium tracking-[0.07em] text-fg-faint uppercase">
        <PairButton
          onClick={onPickSource}
          hint="source"
          uncertain={sourceDetected}
          label={result.source_lang ? languageName(result.source_lang) : "Auto"}
        />
        <span aria-hidden>→</span>
        <PairButton
          onClick={onPickTarget}
          hint="target"
          label={languageName(result.target_lang)}
        />
      </h2>
      {result.translation ? (
        <p
          data-selectable
          className="text-[14px] leading-snug break-words whitespace-pre-wrap"
        >
          {result.translation}
        </p>
      ) : (
        <Muted>unavailable</Muted>
      )}
    </div>
  );
}

/** One half of the language pair — a click target that does not look like a button. */
function PairButton({
  onClick,
  label,
  hint,
  uncertain,
}: {
  onClick: () => void;
  label: string;
  /** Which side this is, spoken: the bare name does not say what changes. */
  hint: "source" | "target";
  /**
   * Detected languages are a guess, so they are italicised the way every other
   * lower-confidence string in this panel is — the domain tag, the truncation
   * note, "unavailable".
   */
  uncertain?: boolean;
}) {
  const title = `Change the ${hint} language — currently ${label}`;

  return (
    <button
      onClick={onClick}
      title={title}
      aria-label={title}
      // focus-visible repeats the hover treatment rather than adding a ring
      // colour the panel does not otherwise have. The native outline is left
      // in place under it — this tint alone is subtle at 10px.
      className={`rounded px-0.5 uppercase hover:bg-hover hover:text-fg-dim focus-visible:bg-hover focus-visible:text-fg-dim ${
        uncertain ? "italic" : ""
      }`}
    >
      {label}
    </button>
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
