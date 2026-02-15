import Combine
import Foundation

final class HistoryViewModel: ObservableObject {

    // MARK: - Published State

    @Published var searchText: String = ""
    @Published var selectedFilter: HistoryFilter = .all
    @Published var groupedEntries: [HistoryGroup] = []
    @Published var totalCount: Int = 0
    @Published var filteredCount: Int = 0
    @Published var availableStyleFilters: [StyleFilterItem] = []
    @Published var selectedEntry: PromptHistoryEntry?
    @Published var showDeleteConfirmation: Bool = false
    @Published var showClearAllConfirmation: Bool = false
    @Published var entryToDelete: UUID?

    // MARK: - Types

    enum HistoryFilter: Equatable {
        case all
        case favorites
        case style(UUID)
    }

    struct StyleFilterItem: Identifiable, Equatable {
        let id: UUID
        let name: String
        let iconName: String
    }

    struct HistoryGroup: Identifiable {
        let id: String
        let title: String
        var entries: [PromptHistoryEntry]
    }

    private let historyService: HistoryService
    private let styleService: StyleService
    private var cancellables = Set<AnyCancellable>()

    init(historyService: HistoryService = .shared, styleService: StyleService = .shared) {
        self.historyService = historyService
        self.styleService = styleService

        // Debounce search text (300ms)
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyFilters()
            }
            .store(in: &cancellables)

        // Immediate response to filter changes
        // Note: @Published fires in willSet, so we use receive(on:) to
        // defer execution until after the property has been updated.
        $selectedFilter
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyFilters()
            }
            .store(in: &cancellables)

        // React to history data changes
        historyService.$entries
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyFilters()
                self?.updateStyleFilters()
            }
            .store(in: &cancellables)

        // Initial load
        applyFilters()
        updateStyleFilters()
    }

    // MARK: - Actions

    func toggleFavorite(_ entryID: UUID) {
        historyService.toggleFavorite(entryID)
    }

    func deleteEntry(_ entryID: UUID) {
        historyService.delete(entryID)
    }

    func confirmDelete() {
        guard let id = entryToDelete else { return }
        deleteEntry(id)
        entryToDelete = nil
    }

    func clearAllHistory() {
        historyService.clearAll()
    }

    func refresh() {
        applyFilters()
        updateStyleFilters()
    }

    func styleName(for styleID: UUID) -> String {
        styleService.getById(styleID)?.displayName ?? "Unknown"
    }

    func styleIcon(for styleID: UUID) -> String {
        styleService.getById(styleID)?.iconName ?? "questionmark"
    }

    /// Look up the project cluster for a history entry's associated context entry.
    func projectCluster(for entryID: UUID) -> ProjectCluster? {
        ContextEngineService.shared.clusterForEntry(promptID: entryID)
    }

    // MARK: - Relative Time Formatting

    func relativeTimestamp(for date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        } else if Calendar.current.isDateInToday(date) {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    // MARK: - Private

    private func applyFilters() {
        var results = historyService.entries
        totalCount = results.count

        // Apply search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            results = results.filter {
                $0.inputText.lowercased().contains(query)
                    || $0.outputText.lowercased().contains(query)
            }
        }

        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .favorites:
            results = results.filter(\.isFavorited)
        case .style(let styleID):
            results = results.filter { $0.styleID == styleID }
        }

        filteredCount = results.count
        groupedEntries = groupByDate(results)
    }

    private func updateStyleFilters() {
        let usedStyleIDs = Set(historyService.entries.map(\.styleID))
        availableStyleFilters = usedStyleIDs.compactMap { id in
            guard let style = styleService.getById(id) else { return nil }
            return StyleFilterItem(id: id, name: style.displayName, iconName: style.iconName)
        }.sorted { $0.name < $1.name }
    }

    private func groupByDate(_ entries: [PromptHistoryEntry]) -> [HistoryGroup] {
        let calendar = Calendar.current
        let now = Date()

        var today: [PromptHistoryEntry] = []
        var yesterday: [PromptHistoryEntry] = []
        var thisWeek: [PromptHistoryEntry] = []
        var older: [PromptHistoryEntry] = []

        for entry in entries {
            if calendar.isDateInToday(entry.timestamp) {
                today.append(entry)
            } else if calendar.isDateInYesterday(entry.timestamp) {
                yesterday.append(entry)
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
                      entry.timestamp > weekAgo {
                thisWeek.append(entry)
            } else {
                older.append(entry)
            }
        }

        var groups: [HistoryGroup] = []
        if !today.isEmpty {
            groups.append(HistoryGroup(id: "today", title: "Today", entries: today))
        }
        if !yesterday.isEmpty {
            groups.append(HistoryGroup(id: "yesterday", title: "Yesterday", entries: yesterday))
        }
        if !thisWeek.isEmpty {
            groups.append(HistoryGroup(id: "thisWeek", title: "This Week", entries: thisWeek))
        }
        if !older.isEmpty {
            groups.append(HistoryGroup(id: "older", title: "Older", entries: older))
        }

        return groups
    }
}
