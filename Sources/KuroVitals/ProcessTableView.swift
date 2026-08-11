import AppKit

/// Table view for the process window, adding the two bits AppKit doesn't give
/// a menu-bar app for free: a ⌘C that copies, and a right-click that acts on
/// the row under the pointer.
final class ProcessTableView: NSTableView {
    /// The app runs as an accessory, so there is no Edit menu to own ⌘C — the
    /// table has to claim the key equivalent itself. Only while it holds focus,
    /// otherwise it would swallow ⌘C from the search field.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command,
           event.charactersIgnoringModifiers == "c",
           window?.firstResponder === self,
           NSApp.sendAction(#selector(ProcessWindowController.copySelectedPID(_:)), to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Select the row under the pointer before showing the menu, so "Copy PID"
    /// copies the row that was right-clicked and not the previous selection.
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        guard clickedRow >= 0 else { return nil }

        if selectedRow != clickedRow {
            selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }
        return super.menu(for: event)
    }
}
