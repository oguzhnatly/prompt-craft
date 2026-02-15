import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel
    var onBack: () -> Void
    var onSelectEntry: (PromptHistoryEntry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            historyHeader
            Divider()

            if viewModel.totalCount == 0 {
                emptyState
            } else {
                historyContent
            }
        }
    }

    // MARK: - Header

    private var historyHeader: some View {
        HStack(spacing: 6) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    onBack()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("History")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to main view")
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 36))
                .foregroundStyle(.secondary.opacity(0.35))
            Text("No optimizations yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Type some text and press Optimize to get started.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(32)
        .pulsingOpacity()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No optimizations yet. Type some text and press Optimize to get started.")
    }

    // MARK: - Content

    private var historyContent: some View {
        List {
            // Top section: count + search + filters
            Section {
                HStack {
                    Text("\(viewModel.totalCount) optimization\(viewModel.totalCount == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)

                searchField
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)

                filterChips
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    .listRowSeparator(.hidden)
            }

            if viewModel.groupedEntries.isEmpty && !viewModel.searchText.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary.opacity(0.35))
                    Text("No results for \"\(viewModel.searchText)\"")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("Try a different search term.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .accessibilityElement(children: .combine)
            } else if viewModel.groupedEntries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary.opacity(0.35))
                    Text("No matching entries")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("Try a different filter.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .accessibilityElement(children: .combine)
            } else {
                ForEach(viewModel.groupedEntries) { group in
                    Section {
                        Text(group.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 2, trailing: 16))
                            .listRowSeparator(.hidden)

                        ForEach(group.entries) { entry in
                            historyRow(entry)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onSelectEntry(entry)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        viewModel.entryToDelete = entry.id
                                        viewModel.showDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        viewModel.toggleFavorite(entry.id)
                                    } label: {
                                        Label(
                                            entry.isFavorited ? "Unfavorite" : "Favorite",
                                            systemImage: entry.isFavorited ? "star.slash" : "star.fill"
                                        )
                                    }
                                    .tint(.yellow)
                                }
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        }
                    }
                }
            }

            // Clear All button at bottom
            if viewModel.totalCount > 0 {
                Section {
                    clearAllButton
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.plain)
        .alert("Delete Entry?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.entryToDelete = nil
            }
            Button("Delete", role: .destructive) {
                viewModel.confirmDelete()
            }
        } message: {
            Text("This will permanently delete this optimization record.")
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Search history...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .padding(.bottom, 6)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(
                    label: "All",
                    isSelected: viewModel.selectedFilter == .all
                ) {
                    viewModel.selectedFilter = .all
                }

                filterChip(
                    label: "Favorites",
                    icon: "star.fill",
                    isSelected: viewModel.selectedFilter == .favorites
                ) {
                    viewModel.selectedFilter = .favorites
                }

                ForEach(viewModel.availableStyleFilters) { styleFilter in
                    filterChip(
                        label: styleFilter.name,
                        icon: styleFilter.iconName,
                        isSelected: viewModel.selectedFilter == .style(styleFilter.id)
                    ) {
                        viewModel.selectedFilter = .style(styleFilter.id)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 4)
    }

    private func filterChip(
        label: String,
        icon: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                action()
            }
        }) {
            HStack(spacing: 3) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9))
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.clear : Color(nsColor: .separatorColor),
                        lineWidth: 0.5
                    )
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(BounceTapStyle())
        .accessibilityLabel("\(label) filter")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func historyRow(_ entry: PromptHistoryEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                // Input preview with search highlight
                if !viewModel.searchText.isEmpty {
                    highlightedText(inputPreview(entry.inputText), highlight: viewModel.searchText)
                        .lineLimit(1)
                } else {
                    Text(inputPreview(entry.inputText))
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 6) {
                    // Style badge
                    HStack(spacing: 3) {
                        Image(systemName: viewModel.styleIcon(for: entry.styleID))
                            .font(.system(size: 8))
                        Text(viewModel.styleName(for: entry.styleID))
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())

                    // Project cluster badge
                    if let cluster = viewModel.projectCluster(for: entry.id) {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color(hex: cluster.color))
                                .frame(width: 6, height: 6)
                            Text(viewModel.projectClusterDisplayName(cluster))
                                .font(.system(size: 9, weight: .medium))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: cluster.color).opacity(0.1))
                        .foregroundStyle(Color(hex: cluster.color))
                        .clipShape(Capsule())
                    }

                    // Timestamp
                    Text(viewModel.relativeTimestamp(for: entry.timestamp))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Favorite star
            Button(action: { viewModel.toggleFavorite(entry.id) }) {
                Image(systemName: entry.isFavorited ? "star.fill" : "star")
                    .font(.system(size: 13))
                    .foregroundStyle(entry.isFavorited ? .yellow : .secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.isFavorited ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button(entry.isFavorited ? "Unfavorite" : "Favorite") {
                viewModel.toggleFavorite(entry.id)
            }
            Divider()
            Button("Delete", role: .destructive) {
                viewModel.deleteEntry(entry.id)
            }
        }
    }

    // MARK: - Search Highlight

    private func highlightedText(_ text: String, highlight: String) -> some View {
        let lowText = text.lowercased()
        let lowHighlight = highlight.lowercased()

        guard let range = lowText.range(of: lowHighlight) else {
            return Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
        }

        let before = String(text[text.startIndex..<range.lowerBound])
        let match = String(text[range])
        let after = String(text[range.upperBound...])

        return Text(before)
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            + Text(match)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.accentColor)
            + Text(after)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
    }

    // MARK: - Helpers

    private func inputPreview(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count > 60 {
            return String(singleLine.prefix(60)) + "..."
        }
        return singleLine
    }

    // MARK: - Clear All

    private var clearAllButton: some View {
        Button(action: {
            viewModel.showClearAllConfirmation = true
        }) {
            HStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                Text("Clear All History")
                    .font(.system(size: 12))
            }
            .foregroundStyle(.red.opacity(0.8))
        }
        .buttonStyle(.plain)
        .alert("Clear All History?", isPresented: $viewModel.showClearAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                viewModel.clearAllHistory()
            }
        } message: {
            Text("This will permanently delete all \(viewModel.totalCount) optimization records. Favorites will also be removed. This cannot be undone.")
        }
    }
}
