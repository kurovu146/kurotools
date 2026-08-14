import { useEffect, useState, type ReactNode } from "react";
import { isSaved, saveWord, speak, ttsAvailable, unsaveWord } from "../store";

/**
 * The save and pronounce buttons on the source pane.
 *
 * Both are best-effort: a storage failure or a missing speech synthesiser must
 * not take down the pane showing the translation the user actually asked for.
 */
export function SourceActions({ text }: { text: string }) {
  const [saved, setSaved] = useState(false);
  const [canSpeak, setCanSpeak] = useState(false);

  useEffect(() => {
    // Gate the speaker button on real availability rather than assuming.
    // Linux may have no synthesiser installed, and a button that silently
    // does nothing is worse than no button.
    void ttsAvailable().then(setCanSpeak);
  }, []);

  useEffect(() => {
    let stale = false;
    void isSaved(text)
      .then((v) => !stale && setSaved(v))
      .catch(() => {});
    // The user can look up a second word before this resolves; without the
    // guard the older answer would overwrite the newer one.
    return () => {
      stale = true;
    };
  }, [text]);

  async function toggleSave() {
    const next = !saved;
    setSaved(next); // optimistic — this button must feel instant
    try {
      await (next ? saveWord(text) : unsaveWord(text));
    } catch {
      setSaved(!next); // put it back; the write did not happen
    }
  }

  return (
    // shrink-0 so a long headword cannot squeeze the buttons out of the row.
    <span className="flex shrink-0 items-center gap-0.5 pt-0.5">
      {canSpeak && (
        <IconButton
          onClick={() => void speak(text).catch(() => {})}
          label="Pronounce"
        >
          <SpeakerIcon />
        </IconButton>
      )}
      <IconButton
        onClick={() => void toggleSave()}
        label={saved ? "Remove from saved words" : "Save this word"}
        pressed={saved}
        active={saved}
      >
        <StarIcon filled={saved} />
      </IconButton>
    </span>
  );
}

/**
 * A square hit target for a 16px glyph.
 *
 * Dimmed until hovered: these sit next to the headword, and at full strength
 * they competed with the word itself for attention.
 */
function IconButton({
  onClick,
  label,
  pressed,
  active,
  children,
}: {
  onClick: () => void;
  label: string;
  pressed?: boolean;
  active?: boolean;
  children: ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      title={label}
      aria-label={label}
      aria-pressed={pressed}
      className={`flex size-6 items-center justify-center rounded-md hover:bg-hover ${
        active ? "text-amber-500" : "text-fg-faint hover:text-fg"
      }`}
    >
      {children}
    </button>
  );
}

function SpeakerIcon() {
  return (
    <svg
      viewBox="0 0 16 16"
      aria-hidden
      className="size-4"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.25"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path
        d="M8.3 3.1 5.3 5.8H3.1a.6.6 0 0 0-.6.6v3.2c0 .33.27.6.6.6h2.2l3 2.7z"
        fill="currentColor"
        stroke="none"
      />
      <path d="M10.8 6.1a2.7 2.7 0 0 1 0 3.8" />
      <path d="M12.7 4.3a5.3 5.3 0 0 1 0 7.4" />
    </svg>
  );
}

function StarIcon({ filled }: { filled: boolean }) {
  return (
    <svg
      viewBox="0 0 16 16"
      aria-hidden
      className="size-4"
      fill={filled ? "currentColor" : "none"}
      stroke="currentColor"
      strokeWidth="1.2"
      strokeLinejoin="round"
    >
      <path d="M8 2.4l1.7 3.44 3.8.55-2.75 2.68.65 3.78L8 11.06l-3.4 1.79.65-3.78L2.5 6.39l3.8-.55z" />
    </svg>
  );
}
