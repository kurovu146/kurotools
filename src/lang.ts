import { invoke } from "@tauri-apps/api/core";

/** The absence of a source language, as the backend spells it. */
export const AUTO = "auto";

/** Mirrors `tra_core::config::LangConfig`. */
export interface LangConfig {
  /** `null` means auto-detect. */
  source: string | null;
  target: string;
  /** The fallback: used when the text is already in `target`. */
  other: string;
}

/**
 * Google's codes are not all valid BCP-47, and `Intl` knows the modern
 * spellings. Display only — never send these to the backend.
 */
const DISPLAY_ALIASES: Record<string, string> = {
  iw: "he",
  jw: "jv",
  "mni-Mtei": "mni",
};

/**
 * Names for codes CLDR does not carry, so the picker never falls back to
 * showing a raw code for a language Google genuinely supports.
 */
const FALLBACK_NAMES: Record<string, string> = {
  ak: "Twi",
  bho: "Bhojpuri",
  doi: "Dogri",
  gom: "Konkani",
  kri: "Krio",
  lus: "Mizo",
  "mni-Mtei": "Meiteilon (Manipuri)",
  nso: "Sepedi",
};

/**
 * The display name for a language code.
 *
 * Derived from `Intl.DisplayNames` rather than a table shipped in the binary:
 * it is already localised, already correct, and a hand-maintained list of 130
 * names would be 130 chances to be wrong — and would itself need translating.
 */
export function languageName(code: string): string {
  if (code === AUTO) return "Auto";

  const fallback = FALLBACK_NAMES[code];
  const resolvedCode = DISPLAY_ALIASES[code] ?? code;
  try {
    const display = new Intl.DisplayNames(navigator.languages as string[], {
      type: "language",
    });
    const name = display.of(resolvedCode);
    // `of` returns its input when it does not know the code. Compare against
    // the code actually passed to `of` — for an aliased code (`iw` → `he`)
    // comparing against the original would make every alias look "resolved".
    if (name && name !== resolvedCode) return name;
  } catch {
    // Intl.DisplayNames is unavailable or the code is malformed. Either way
    // a name is cosmetic — never let it break the picker.
  }
  return fallback ?? code;
}

export async function languages(): Promise<string[]> {
  return await invoke<string[]>("languages");
}

export async function langConfig(): Promise<LangConfig> {
  return await invoke<LangConfig>("lang_config");
}

/**
 * Store a configuration and return what was actually stored.
 *
 * The backend repairs colliding languages, so the result can differ from the
 * request. Render the response, never an optimistic local guess.
 */
export async function setLangConfig(config: LangConfig): Promise<LangConfig> {
  return await invoke<LangConfig>("set_lang_config", {
    source: config.source,
    target: config.target,
    other: config.other,
  });
}

export async function recentLanguages(): Promise<string[]> {
  return await invoke<string[]>("recent_languages");
}
