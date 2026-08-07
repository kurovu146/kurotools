import { useEffect, useState } from "react";
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
    <span className="flex items-center gap-1">
      {canSpeak && (
        <button
          onClick={() => void speak(text).catch(() => {})}
          title="Pronounce"
          aria-label="Pronounce"
          className="rounded px-1 text-neutral-500 hover:bg-neutral-100 hover:text-neutral-800 dark:text-neutral-400 dark:hover:bg-neutral-800 dark:hover:text-neutral-100"
        >
          ►
        </button>
      )}
      <button
        onClick={() => void toggleSave()}
        title={saved ? "Remove from saved words" : "Save this word"}
        aria-label={saved ? "Remove from saved words" : "Save this word"}
        aria-pressed={saved}
        className={
          saved
            ? "rounded px-1 text-amber-500"
            : "rounded px-1 text-neutral-400 hover:bg-neutral-100 hover:text-neutral-700 dark:hover:bg-neutral-800 dark:hover:text-neutral-200"
        }
      >
        {saved ? "★" : "☆"}
      </button>
    </span>
  );
}
