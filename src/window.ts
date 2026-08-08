import { getCurrentWindow, LogicalSize } from "@tauri-apps/api/window";
import { useEffect, useRef, type MouseEvent as ReactMouseEvent } from "react";

/**
 * Apply the OS appearance as a `dark` class on `<html>`.
 *
 * Read from Tauri rather than `prefers-color-scheme`: through a transparent,
 * vibrancy-backed window the webview reported *light* on a dark system, which
 * rendered the panel as a flat grey slab instead of a dark translucent one.
 * Tauri asks AppKit directly and gets the right answer.
 */
export function useSystemTheme() {
  useEffect(() => {
    const win = getCurrentWindow();

    const apply = (theme: string | null) => {
      document.documentElement.classList.toggle("dark", theme === "dark");
    };

    void win.theme().then(apply);
    // The user can switch appearance while the app is running, and a tray
    // utility lives across that easily.
    const unlisten = win.onThemeChanged(({ payload }) => apply(payload));

    return () => {
      void unlisten.then((f) => f());
    };
  }, []);
}

/**
 * Drag the whole window from wherever the pointer went down.
 *
 * The popup has no titlebar to grab — that is the point of it — so the panel
 * itself has to be the handle. Two carve-outs:
 *
 * - Controls own their clicks, or the speak and save buttons would move the
 *   window instead of firing.
 * - Anything marked `data-selectable` stays selectable, so the definitions and
 *   the translation can still be copied. Everything else — the headword row
 *   and the panel's background — drags, which keeps the grab area large enough
 *   to find without a visible handle.
 *
 * `startDragging` hands the gesture straight to the window server, so there is
 * no drag threshold to wait for and no way to change our mind afterwards. That
 * is why the exclusions are decided here, on mousedown, rather than by
 * watching how far the pointer travels.
 */
export function startWindowDrag(event: ReactMouseEvent<HTMLElement>) {
  if (event.button !== 0) return;

  const target = event.target as HTMLElement;
  if (target.closest("button, input, textarea, a, [data-selectable]")) return;

  event.preventDefault();
  void getCurrentWindow().startDragging();
}

/** Never grow past this, however long the translation is — scroll instead. */
const MAX_HEIGHT = 520;
/** Below this the panel looks broken rather than compact. */
const MIN_HEIGHT = 56;

/**
 * Size the window to its content, the way the system Look Up panel does.
 *
 * A fixed height leaves a large empty area under a short translation, which is
 * the single most obvious way this looked unlike the panel it is imitating.
 *
 * Returns a ref to attach to the element being measured.
 */
export function useHeightFitsContent<T extends HTMLElement>() {
  const ref = useRef<T | null>(null);

  useEffect(() => {
    const element = ref.current;
    if (!element) return;

    const win = getCurrentWindow();
    let last = 0;

    const resize = () => {
      // scrollHeight, not clientHeight: clientHeight is the height the window
      // already has, so measuring it would just confirm the current size and
      // the panel would never shrink.
      const wanted = Math.min(
        MAX_HEIGHT,
        Math.max(MIN_HEIGHT, Math.ceil(element.scrollHeight)),
      );
      // A pixel or two of jitter would otherwise resize the window on every
      // observation, which reads as flicker.
      if (Math.abs(wanted - last) < 4) return;
      last = wanted;
      void win.innerSize().then((size) =>
        win.scaleFactor().then((scale) => {
          void win.setSize(new LogicalSize(size.width / scale, wanted));
        }),
      );
    };

    const observer = new ResizeObserver(resize);
    observer.observe(element);
    resize();

    return () => observer.disconnect();
  }, []);

  return ref;
}
