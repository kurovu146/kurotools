import { invoke } from "@tauri-apps/api/core";

/** Mirrors `tra_core::store::SavedWord`. */
export interface SavedWord {
  word: string;
  /** Unix seconds. */
  saved_at: number;
}

/** Mirrors `tra_core::store::HistoryEntry`. */
export interface HistoryEntry {
  id: number;
  source: string;
  translation: string | null;
  /** Unix seconds. */
  looked_up_at: number;
}

export async function saveWord(word: string): Promise<void> {
  await invoke("save_word", { word });
}

export async function unsaveWord(word: string): Promise<void> {
  await invoke("unsave_word", { word });
}

export async function isSaved(word: string): Promise<boolean> {
  return await invoke<boolean>("is_saved", { word });
}

export async function savedWords(): Promise<SavedWord[]> {
  return await invoke<SavedWord[]>("saved_words");
}

export async function recentLookups(limit = 50): Promise<HistoryEntry[]> {
  return await invoke<HistoryEntry[]>("recent_lookups", { limit });
}

export async function speak(text: string): Promise<void> {
  await invoke("speak", { text });
}

export async function ttsAvailable(): Promise<boolean> {
  return await invoke<boolean>("tts_available");
}
