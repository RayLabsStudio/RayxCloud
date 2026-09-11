// LibraryView.swift
// Cloud game grid. Tap a game to start streaming it.
//

import SwiftUI
import StratixCore
import StratixModels

struct LibraryView: View {
    @Environment(SessionController.self) private var sessionController
    @Environment(LibraryController.self) private var libraryController
    @Environment(ShellBootstrapController.self) private var bootstrapController

    @State private var query = ""
    @State private var selectedTitle: CloudLibraryItem?
    @State private var filter = LibraryFilter()

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12)]

    private var allItems: [CloudLibraryItem] {
        Array(libraryController.itemsByTitleID.values)
    }

    /// Union of catalog capability names, used to build the filter menu.
    private var availableFeatures: [String] {
        var names = Set<String>()
        for item in allItems {
            for attribute in item.attributes {
                let name = attribute.localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { names.insert(name) }
            }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var items: [CloudLibraryItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = allItems.filter { item in
            if !trimmedQuery.isEmpty, !item.name.localizedCaseInsensitiveContains(trimmedQuery) {
                return false
            }
            return filter.matches(item)
        }
        return filtered.sorted { lhs, rhs in
            if filter.sort == .recentFirst, lhs.isInMRU != rhs.isInMRU { return lhs.isInMRU }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var isInitialLoad: Bool {
        libraryController.itemsByTitleID.isEmpty
            && (libraryController.isLoading || bootstrapController.isLoading)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isInitialLoad {
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text(bootstrapController.statusText ?? "Loading your games")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if libraryController.itemsByTitleID.isEmpty {
                    ContentUnavailableView {
                        Label("No games yet", systemImage: "gamecontroller")
                    } description: {
                        Text(libraryController.lastError ?? "Pull down to refresh your Game Pass library.")
                    } actions: {
                        Button("Refresh") {
                            Task { await libraryController.refresh(forceRefresh: true, reason: .manualUser) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                } else {
                    ScrollView {
                        if items.isEmpty {
                            ContentUnavailableView.search(text: query)
                                .padding(.top, 60)
                        } else {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(items) { item in
                                    Button {
                                        selectedTitle = item
                                    } label: {
                                        GameTile(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(16)
                        }
                    }
                    .refreshable {
                        await libraryController.refresh(forceRefresh: true, reason: .manualUser)
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        searchAndFilterBar
                    }
                }
            }
            .background(Color.black)
            .navigationTitle("Game Pass")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
#endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Refresh library") {
                            Task { await libraryController.refresh(forceRefresh: true, reason: .manualUser) }
                        }
                        Button("Sign out", role: .destructive) {
                            Task { await sessionController.signOut() }
                        }
                    } label: {
                        RoundIcon(symbol: "person.fill", tint: .green, size: 34)
                    }
                    .iconMenuStyle()
                }
            }
        }
        .tint(.green)
#if os(iOS)
        .fullScreenCover(item: $selectedTitle) { item in
            StreamView(item: item) { selectedTitle = nil }
        }
#else
        .overlay {
            if let item = selectedTitle {
                StreamView(item: item) { selectedTitle = nil }
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 900, minHeight: 560)
#endif
    }
}

extension LibraryView {
    /// Search field with the filter button on its right.
    private var searchAndFilterBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search games", text: $query)
                    .textFieldStyle(.plain)
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .capsuleGlass()

            filterMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
    }

    private var filterMenu: some View {
        Menu {
            Section("Show") {
                Toggle("Recently played", isOn: $filter.recentOnly)
                Toggle("Touch controls", isOn: $filter.touchOnly)
            }
            if !availableFeatures.isEmpty {
                Section("Feature") {
                    Picker("Feature", selection: $filter.feature) {
                        Text("Any").tag(String?.none)
                        ForEach(availableFeatures, id: \.self) { feature in
                            Text(feature).tag(String?.some(feature))
                        }
                    }
                }
            }
            Section("Sort") {
                Picker("Sort", selection: $filter.sort) {
                    ForEach(LibraryFilter.Sort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
            }
            if filter.isActive {
                Section {
                    Button("Clear filters", role: .destructive) {
                        filter = LibraryFilter()
                    }
                }
            }
        } label: {
            RoundIcon(symbol: "line.3.horizontal.decrease", tint: filter.isActive ? .green : .white)
        }
        .iconMenuStyle()
        .accessibilityLabel("Filter games")
    }
}

/// Library filter state. Kept as a plain value so the menu bindings stay simple.
struct LibraryFilter: Equatable {
    enum Sort: String, CaseIterable, Identifiable {
        case recentFirst
        case alphabetical

        var id: String { rawValue }

        var title: String {
            switch self {
            case .recentFirst: return "Recently played first"
            case .alphabetical: return "A to Z"
            }
        }
    }

    var recentOnly = false
    var touchOnly = false
    var feature: String?
    var sort: Sort = .recentFirst

    var isActive: Bool {
        recentOnly || touchOnly || feature != nil || sort != .recentFirst
    }

    func matches(_ item: CloudLibraryItem) -> Bool {
        if recentOnly, !item.isInMRU { return false }
        if touchOnly, !item.supportedInputTypes.contains(where: { $0.localizedCaseInsensitiveContains("touch") }) {
            return false
        }
        if let feature, !item.attributes.contains(where: { $0.localizedName == feature }) {
            return false
        }
        return true
    }
}

private struct GameTile: View {
    let item: CloudLibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(urls: [item.posterImageURL, item.artURL, item.heroImageURL], maxPixelSize: 800) {
                placeholder
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(item.name)
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .overlay(
                Image(systemName: "gamecontroller")
                    .foregroundStyle(.white.opacity(0.4))
            )
    }
}
