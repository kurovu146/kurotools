import AppKit
import SystemStats

@MainActor
final class ProcessWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation {
    private enum Column {
        static let name = NSUserInterfaceItemIdentifier("name")
        static let pid = NSUserInterfaceItemIdentifier("pid")
        static let ports = NSUserInterfaceItemIdentifier("ports")
        static let cpu = NSUserInterfaceItemIdentifier("cpu")
        static let memory = NSUserInterfaceItemIdentifier("memory")
    }

    /// Sampling cadence. `ps` is cheap; `lsof` is not, so ports are rescanned
    /// only every few ticks (~9s) — listening ports barely move.
    private static let refreshSeconds: TimeInterval = 3.0
    private static let portsRefreshEveryTicks = 3

    private let sampler: ProcessSampler
    private let samplerQueue = DispatchQueue(label: "com.kurovitals.process-sampler", qos: .utility)
    private let searchField = NSSearchField()
    private let refreshButton = NSButton()
    private let killButton = NSButton()
    private let tableView = ProcessTableView()
    private let statusLabel = NSTextField(labelWithString: "")

    private var refreshTimer: Timer?
    private var model = ProcessTableModel()
    private var tickCount = 0
    private var isSampling = false
    private var isRestoringSelection = false
    private var isShowingAlert = false

    init(sampler: ProcessSampler = ProcessSampler()) {
        self.sampler = sampler

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_020, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tiến trình đang chạy"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 860, height: 420)

        super.init(window: window)
        window.delegate = self
        buildInterface()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAndRefresh() {
        if window?.isVisible != true {
            window?.center()
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        startRefreshTimer()
        reloadProcesses(forcePorts: true)
    }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        model.rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, row < model.rows.count else { return nil }
        let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NSTableCellView
            ?? makeCell(identifier: tableColumn.identifier)
        let process = model.rows[row]

        switch tableColumn.identifier {
        case Column.name:
            cell.textField?.stringValue = process.name
            cell.textField?.toolTip = process.command
            cell.textField?.lineBreakMode = .byTruncatingMiddle
        case Column.pid:
            cell.textField?.stringValue = "\(process.pid)"
            cell.textField?.toolTip = nil
            cell.textField?.lineBreakMode = .byTruncatingTail
        case Column.ports:
            cell.textField?.stringValue = Self.portsTitle(process.ports)
            cell.textField?.toolTip = process.ports.isEmpty ? nil : process.ports.map(String.init).joined(separator: ", ")
            cell.textField?.lineBreakMode = .byTruncatingTail
        case Column.cpu:
            cell.textField?.stringValue = String(format: "%.1f%%", process.cpuPercent)
            cell.textField?.toolTip = nil
            cell.textField?.lineBreakMode = .byTruncatingTail
        case Column.memory:
            cell.textField?.stringValue = Self.memoryTitle(bytes: process.residentMemoryBytes)
            cell.textField?.toolTip = nil
            cell.textField?.lineBreakMode = .byTruncatingTail
        default:
            cell.textField?.stringValue = ""
        }

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isRestoringSelection else { return }
        // Selecting a row freezes the order; deselecting lets the next tick sort again.
        let row = tableView.selectedRow
        model.selectedPID = row >= 0 && row < model.rows.count ? model.rows[row].pid : nil
        updateKillButton()
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        applySortDescriptor()
        model.rebuild()
        reloadTable()
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.alignment = .centerY

        searchField.placeholderString = "Search by name, PID, or port"
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        refreshButton.title = "Refresh"
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        refreshButton.imagePosition = .imageLeading
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked(_:))

        killButton.title = "Kill"
        killButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Kill")
        killButton.imagePosition = .imageLeading
        killButton.target = self
        killButton.action = #selector(killSelectedProcess(_:))
        killButton.isEnabled = false

        toolbar.addArrangedSubview(searchField)
        toolbar.addArrangedSubview(refreshButton)
        toolbar.addArrangedSubview(killButton)
        root.addArrangedSubview(toolbar)

        configureTable()
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        root.addArrangedSubview(scrollView)
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(statusLabel)
    }

    private func configureTable() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.rowHeight = 24
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.sortDescriptors = [NSSortDescriptor(key: "cpu", ascending: false)]

        let contextMenu = NSMenu()
        let copyItem = NSMenuItem(title: "Copy PID", action: #selector(copySelectedPID(_:)), keyEquivalent: "c")
        copyItem.target = self
        contextMenu.addItem(copyItem)
        tableView.menu = contextMenu

        addColumn(identifier: Column.name, title: "Tên", width: 430, minWidth: 240, sortKey: "name")
        addColumn(identifier: Column.pid, title: "PID", width: 90, minWidth: 70, sortKey: "pid")
        addColumn(identifier: Column.ports, title: "Ports", width: 190, minWidth: 120, sortKey: "ports")
        addColumn(identifier: Column.cpu, title: "CPU", width: 100, minWidth: 80, sortKey: "cpu")
        addColumn(identifier: Column.memory, title: "RAM", width: 130, minWidth: 100, sortKey: "memory")
        applySortDescriptor()
    }

    private func addColumn(identifier: NSUserInterfaceItemIdentifier,
                           title: String,
                           width: CGFloat,
                           minWidth: CGFloat,
                           sortKey: String) {
        let column = NSTableColumn(identifier: identifier)
        column.title = title
        column.width = width
        column.minWidth = minWidth
        column.resizingMask = .userResizingMask
        column.sortDescriptorPrototype = NSSortDescriptor(key: sortKey, ascending: true)
        tableView.addTableColumn(column)
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        if identifier != Column.name && identifier != Column.ports {
            textField.alignment = .right
            textField.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        } else if identifier == Column.ports {
            textField.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }

        cell.addSubview(textField)
        cell.textField = textField
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: Self.refreshSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadProcesses() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    @objc private func refreshClicked(_ sender: NSButton) {
        reloadProcesses(forcePorts: true)
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        model.query = searchField.stringValue
        model.rebuild()
        reloadTable()
    }

    private func applySortDescriptor() {
        guard let descriptor = tableView.sortDescriptors.first else { return }
        model.sortKey = descriptor.key.flatMap(ProcessSortKey.init(rawValue:)) ?? .cpu
        model.ascending = descriptor.ascending
    }

    /// Samples off the main thread — `ps` plus `lsof` would otherwise stall the
    /// UI for long enough to make clicking a row unreliable.
    private func reloadProcesses(forcePorts: Bool = false) {
        // A modal kill confirmation runs the timer in .common mode; don't move
        // the table out from under the alert.
        guard !isShowingAlert, !isSampling else { return }
        isSampling = true

        let refreshPorts = forcePorts || tickCount % Self.portsRefreshEveryTicks == 0
        tickCount += 1
        let sampler = sampler

        samplerQueue.async { [weak self] in
            let result = Result { try sampler.listProcesses(refreshPorts: refreshPorts) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.apply(result) }
            }
        }
    }

    private func apply(_ result: Result<[RunningProcess], Error>) {
        isSampling = false
        switch result {
        case .success(let processes):
            model.refresh(with: processes)
            reloadTable()
        case .failure(let error):
            statusLabel.stringValue = "Không đọc được danh sách tiến trình: \(error.localizedDescription)"
        }
    }

    /// `reloadData` only preserves the selected *index*, which after a re-sort
    /// points at some other process — re-anchor the selection on its PID.
    private func reloadTable() {
        let selectedPID = model.selectedPID
        tableView.reloadData()

        if let selectedPID, let row = model.index(of: selectedPID) {
            if tableView.selectedRow != row {
                isRestoringSelection = true
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                isRestoringSelection = false
            }
        } else if tableView.selectedRow >= 0 || selectedPID != nil {
            // The selected process is gone (killed or filtered out).
            model.selectedPID = nil
            tableView.deselectAll(nil)
        }

        updateKillButton()
        updateStatus()
    }

    private func updateKillButton() {
        killButton.isEnabled = selectedProcess != nil
    }

    private func updateStatus() {
        let query = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            statusLabel.stringValue = "\(model.rows.count) tiến trình"
        } else {
            statusLabel.stringValue = "\(model.rows.count) kết quả cho \"\(query)\""
        }
    }

    private var selectedProcess: RunningProcess? {
        let row = tableView.selectedRow
        guard row >= 0, row < model.rows.count else { return nil }
        return model.rows[row]
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(copySelectedPID(_:)) else { return true }
        return selectedProcess != nil
    }

    @objc func copySelectedPID(_ sender: Any?) {
        guard let process = selectedProcess else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("\(process.pid)", forType: .string)
        // The next sample (~3s) puts the process count back.
        statusLabel.stringValue = "Đã copy PID \(process.pid)"
    }

    @objc private func killSelectedProcess(_ sender: NSButton) {
        guard let process = selectedProcess, let window else { return }

        let alert = NSAlert()
        alert.messageText = "Kill \(process.name)?"
        alert.informativeText = "PID \(process.pid) - \(process.command)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Kill")
        alert.addButton(withTitle: "Cancel")

        isShowingAlert = true
        let response = alert.runModal()
        isShowingAlert = false
        guard response == .alertFirstButtonReturn else { return }

        do {
            try terminateProcess(pid: process.pid)
            // The row is about to disappear — drop the freeze and re-sort.
            model.selectedPID = nil
            tableView.deselectAll(nil)
            reloadProcesses(forcePorts: true)
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Không kill được \(process.name)"
            errorAlert.informativeText = error.localizedDescription
            errorAlert.alertStyle = .warning
            errorAlert.beginSheetModal(for: window)
        }
    }

    private static func memoryTitle(bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1_024 {
            return String(format: "%.2f GB", mb / 1_024.0)
        }
        return String(format: "%.0f MB", mb)
    }

    private static func portsTitle(_ ports: [Int]) -> String {
        guard !ports.isEmpty else { return "-" }
        return ports.prefix(4).map(String.init).joined(separator: ", ")
            + (ports.count > 4 ? " +" : "")
    }
}
