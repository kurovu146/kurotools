import { useEffect, useState } from "react";
import {
  checkAccessibility,
  openAccessibilitySettings,
  requestAccessibility,
  setDismissOnBlur,
} from "../capture";

/** How often to re-check while the gate is showing. */
const POLL_MS = 500;

/**
 * Shown when macOS Accessibility has not been granted.
 *
 * Three things this must do, all learned from how badly the default flow goes:
 *
 * 1. **Explain before asking.** macOS's own dialog says nothing about why, so
 *    a cold prompt reads as an app demanding control of your computer.
 * 2. **Poll for the grant.** `onGranted` fires the moment permission appears,
 *    so nobody has to restart the app. Requiring a restart here loses people.
 * 3. **Never dead-end.** Declining is a supported choice: copy-then-hotkey
 *    needs no permission at all. "Continue without it" is a real path, not a
 *    consolation prize — it is also the only path on GNOME/Wayland.
 */
export function PermissionGate({
  onGranted,
  onSkip,
}: {
  onGranted: () => void;
  onSkip: () => void;
}) {
  const [asked, setAsked] = useState(false);

  // Clicking "Grant access" opens System Settings, which takes focus away. The
  // window's blur handler would otherwise hide this screen the instant the
  // user acts on it, leaving them staring at System Settings with no idea what
  // they were meant to do. Restored on unmount so the popup dismisses normally
  // again.
  useEffect(() => {
    void setDismissOnBlur(false);
    return () => {
      void setDismissOnBlur(true);
    };
  }, []);

  useEffect(() => {
    // Polling rather than a one-shot check: the user grants permission in
    // System Settings, a different process entirely, and nothing notifies us.
    const id = setInterval(async () => {
      // checkAccessibility, not requestAccessibility: this must not re-raise
      // the system dialog twice a second while the user reads it.
      if (await checkAccessibility()) {
        clearInterval(id);
        onGranted();
      }
    }, POLL_MS);
    return () => clearInterval(id);
  }, [onGranted]);

  return (
    <div className="flex flex-col gap-3 p-4 text-[13px]">
      <h1 className="text-[15px] font-semibold">Let Tra read your selection</h1>

      <p className="text-fg-dim">
        To look up the text you highlight in other apps, macOS requires
        Accessibility access. Tra uses it for one thing only: copying your
        current selection when you press the hotkey. Your clipboard is put back
        exactly as it was.
      </p>

      <div className="flex flex-col gap-2 pt-1">
        <button
          className="rounded-md bg-sky-600 px-3 py-2 font-medium text-white hover:bg-sky-500"
          onClick={async () => {
            setAsked(true);
            await requestAccessibility();
            await openAccessibilitySettings();
          }}
        >
          {asked ? "Open System Settings again" : "Grant access"}
        </button>

        <button
          className="rounded-md px-3 py-2 text-fg-dim hover:bg-hover"
          onClick={onSkip}
        >
          Continue without it
        </button>
      </div>

      <p className="text-[12px] text-fg-faint">
        Without access, Tra still works — copy the text first, then press the
        hotkey.
      </p>
    </div>
  );
}
