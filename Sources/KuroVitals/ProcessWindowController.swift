import AppKit
import SystemStats

@MainActor
final class ProcessWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private enum Column {
        static let name = NSUserInterfaceItemIdentifier("name")
        static let pid = NSUserInterfaceItemIdentifier("pid")
        static let ports = NSUserInterfaceItemIdentifier("ports")
        static let cpu = NSUserInterfaceItemIdentifier("cpu")
        static let memory = NSUserInterfaceItemIdentifier("memory")
    }

    private let sampler: ProcessSampler
    private let searchField = NSSearchField()
    private let refreshButton = NSButton()
    private let killButton = NSButton()
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")

    private var refreshTimer: Timer?
    private var allProcesses: [RunningProcess] = []
    private var filteredProcesses: [RunningProcess] = []

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
        reloadProcesses()
    }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredProcesses.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, row < filteredProcesses.count else { return nil }
        let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NSTableCellView
            ?? makeCell(identifier: tableColumn.identifier)
        let process = filteredProcesses[row]

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
        updateKillButton()
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        applyFilterAndSort()
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

        addColumn(identifier: Column.name, title: "Tên", width: 430, minWidth: 240, sortKey: "name")
        addColumn(identifier: Column.pid, title: "PID", width: 90, minWidth: 70, sortKey: "pid")
        addColumn(identifier: Column.ports, title: "Ports", width: 190, minWidth: 120, sortKey: "ports")
        addColumn(identifier: Column.cpu, title: "CPU", width: 100, minWidth: 80, sortKey: "cpu")
        addColumn(identifier: Column.memory, title: "RAM", width: 130, minWidth: 100, sortKey: "memory")
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
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadProcesses() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    @objc private func refreshClicked(_ sender: NSButton) {
        reloadProcesses()
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        applyFilterAndSort()
    }

    private func reloadProcesses() {
        do {
            allProcesses = try sampler.listProcesses()
            applyFilterAndSort()
        } catch {
            statusLabel.stringValue = "Không đọc được danh sách tiến trình: \(error.localizedDescription)"
        }
    }

    private func applyFilterAndSort() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filteredProcesses = allProcesses
        } else {
            filteredProcesses = allProcesses.filter { process in
                process.name.localizedCaseInsensitiveContains(query)
                    || process.command.localizedCaseInsensitiveContains(query)
                    || String(process.pid).contains(query)
                    || process.ports.contains { String($0).contains(query) }
            }
        }

        sortFilteredProcesses()
        tableView.reloadData()
        updateKillButton()
        updateStatus(query: query)
    }

    private func sortFilteredProcesses() {
        guard let descriptor = tableView.sortDescriptors.first else { return }
        let ascending = descriptor.ascending

        switch descriptor.key {
        case "name":
            filteredProcesses.sort {
                ascending
                    ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending
            }
        case "pid":
            filteredProcesses.sort { ascending ? $0.pid < $1.pid : $0.pid > $1.pid }
        case "ports":
            filteredProcesses.sort {
                let lhs = $0.ports.first ?? Int.max
                let rhs = $1.ports.first ?? Int.max
                return ascending ? lhs < rhs : lhs > rhs
            }
        case "memory":
            filteredProcesses.sort {
                ascending
                    ? $0.residentMemoryBytes < $1.residentMemoryBytes
                    : $0.residentMemoryBytes > $1.residentMemoryBytes
            }
        default:
            filteredProcesses.sort {
                ascending
                    ? $0.cpuPercent < $1.cpuPercent
                    : $0.cpuPercent > $1.cpuPercent
            }
        }
    }

    private func updateKillButton() {
        killButton.isEnabled = selectedProcess != nil
    }

    private func updateStatus(query: String) {
        if query.isEmpty {
            statusLabel.stringValue = "\(filteredProcesses.count) tiến trình"
        } else {
            statusLabel.stringValue = "\(filteredProcesses.count) kết quả cho \"\(query)\""
        }
    }

    private var selectedProcess: RunningProcess? {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredProcesses.count else { return nil }
        return filteredProcesses[row]
    }

    @objc private func killSelectedProcess(_ sender: NSButton) {
        guard let process = selectedProcess, let window else { return }

        let alert = NSAlert()
        alert.messageText = "Kill \(process.name)?"
        alert.informativeText = "PID \(process.pid) - \(process.command)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Kill")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try terminateProcess(pid: process.pid)
            reloadProcesses()
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
