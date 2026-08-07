import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

/** Mirrors `popup::CaptureEvent`. */
export type CaptureEvent =
  | { kind: "text"; text: string }
  | { kind: "empty" }
  | { kind: "needsPermission" };

/** Emitted by the shell after the hotkey fires. Must match `CAPTURE_EVENT`. */
const CAPTURE_EVENT = "tra://capture";

export function onCapture(handler: (e: CaptureEvent) => void) {
  return listen<CaptureEvent>(CAPTURE_EVENT, (event) => handler(event.payload));
}

/** Dismiss the popup. Hiding is the shell's job, not the webview's. */
export async function hidePopup(): Promise<void> {
  await invoke("hide_popup");
}

export async function checkAccessibility(): Promise<boolean> {
  return await invoke<boolean>("check_accessibility");
}

export async function requestAccessibility(): Promise<boolean> {
  return await invoke<boolean>("request_accessibility");
}

export async function openAccessibilitySettings(): Promise<void> {
  await invoke("open_accessibility_settings");
}
