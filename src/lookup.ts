import { invoke } from "@tauri-apps/api/core";

/** Mirrors `tra_core::model::Definition`. */
export interface Definition {
  part_of_speech: string;
  /** Absent for most words. Present for domain-specific senses. */
  domain: string | null;
  gloss: string;
}

/** Mirrors `tra_core::model::Lookup`. */
export interface Lookup {
  source: string;
  /** The source text was cut before being sent, and the UI must say so. */
  source_truncated: boolean;
  definitions: Definition[];
  /** `null` means the provider could not answer — render "unavailable". */
  translation: string | null;
}

/**
 * Look text up.
 *
 * The Rust side never fails: an unreachable network yields a `Lookup` with no
 * translation and no definitions rather than an error. This wrapper keeps that
 * contract so no caller needs a try/catch to render a result.
 */
export async function lookup(text: string): Promise<Lookup> {
  return await invoke<Lookup>("lookup", { text });
}
