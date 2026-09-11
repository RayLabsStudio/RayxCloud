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
#if os(macOS)
    private var windowState: MacWindowState { MacWindowState.shared }
#endif

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12)]

    private var allItems: [CloudLibraryItem] {
        Array(libraryController.itemsByTitleID.values)
    }

    /// Catalog capabilities present in the library, normalized and grouped for the menu.
    private var featureGroups: [FeatureGroup] {
        var names = Set<String>()
        for item in allItems {
            for attribute in item.attributes {
                let name = LibraryFilter.normalizedFeature(attribute.localizedName)
                if !name.isEmpty { names.insert(name) }
            }
        }
        return FeatureGroup.group(names)
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
#if os(iOS)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    profileMenu
                }
            }
#else
            .toolbar(.hidden, for: .windowToolbar)
#endif
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
#if os(macOS)
            profileMenu
#endif
        }
#if os(macOS)
        .padding(.leading, 16 + windowState.leadingInset)
        .padding(.trailing, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
#else
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
#endif
        .background(Color.black)
    }

    private var profileMenu: some View {
        Menu {
            Button("Refresh library") {
                Task { await libraryController.refresh(forceRefresh: true, reason: .manualUser) }
            }
            Button("Sign out", role: .destructive) {
                Task { await sessionController.signOut() }
            }
        } label: {
            RoundIcon(symbol: "person.fill", tint: .green, size: 40)
        }
        .iconMenuStyle()
        .accessibilityLabel("Account")
    }

    private var filterMenu: some View {
        Menu {
            Section("Show") {
                Toggle("Recently played", isOn: $filter.recentOnly)
                Toggle("Touch controls", isOn: $filter.touchOnly)
            }

            Section("Players") {
                Picker("Players", selection: $filter.minPlayers) {
                    Text("Any").tag(Int?.none)
                    Text("2 or more").tag(Int?.some(2))
                    Text("4 or more").tag(Int?.some(4))
                    Text("8 or more").tag(Int?.some(8))
                    Text("16 or more").tag(Int?.some(16))
                }
                .pickerStyle(.inline)
            }

            Section("Feature") {
                if filter.feature != nil {
                    Button("Any feature") { filter.feature = nil }
                }
                ForEach(featureGroups) { group in
                    Menu(group.title) {
                        Picker(group.title, selection: $filter.feature) {
                            ForEach(group.features, id: \.self) { feature in
                                Text(feature).tag(String?.some(feature))
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }
            }

            Section("Sort") {
                Picker("Sort", selection: $filter.sort) {
                    ForEach(LibraryFilter.Sort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.inline)
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

/// A named bucket of normalized catalog features for the filter menu.
struct FeatureGroup: Identifiable {
    let title: String
    let features: [String]

    var id: String { title }

    static func group(_ names: Set<String>) -> [FeatureGroup] {
        var together: [String] = []
        var picture: [String] = []
        var other: [String] = []
        for name in names {
            let lower = name.lowercased()
            if lower.contains("co-op") || lower.contains("coop") || lower.contains("multiplayer")
                || lower.contains("cross-") || lower.contains("cross platform") || lower.contains("single player") {
                together.append(name)
            } else if lower.contains("4k") || lower.contains("hdr") || lower.contains("dolby") || lower.contains("dts")
                || lower.contains("spatial") || lower.contains("fps") || lower.contains("ray tracing")
                || lower.contains("optimized") || lower.contains("refresh") || lower.contains("1080") || lower.contains("120") {
                picture.append(name)
            } else {
                other.append(name)
            }
        }
        let sort: (String, String) -> Bool = { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return [
            FeatureGroup(title: "Play together", features: together.sorted(by: sort)),
            FeatureGroup(title: "Picture and sound", features: picture.sorted(by: sort)),
            FeatureGroup(title: "More", features: other.sorted(by: sort))
        ].filter { !$0.features.isEmpty }
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
    var minPlayers: Int?
    var sort: Sort = .recentFirst

    var isActive: Bool {
        recentOnly || touchOnly || feature != nil || minPlayers != nil || sort != .recentFirst
    }

    func matches(_ item: CloudLibraryItem) -> Bool {
        if recentOnly, !item.isInMRU { return false }
        if touchOnly, !item.supportedInputTypes.contains(where: { $0.localizedCaseInsensitiveContains("touch") }) {
            return false
        }
        if let feature,
           !item.attributes.contains(where: { Self.normalizedFeature($0.localizedName) == feature }) {
            return false
        }
        if let minPlayers, Self.maxPlayers(of: item) < minPlayers {
            return false
        }
        return true
    }

    /// "Online co-op (2-12)" becomes "Online co-op" so player-count variants collapse into one entry.
    static func normalizedFeature(_ localizedName: String) -> String {
        var name = localizedName
        if let range = name.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Largest player count advertised by any multiplayer or co-op attribute. Single-player titles return 1.
    static func maxPlayers(of item: CloudLibraryItem) -> Int {
        var best = 1
        for attribute in item.attributes {
            guard let range = attribute.localizedName.range(of: #"\((\d+)(?:\s*-\s*(\d+))?\)"#, options: .regularExpression) else { continue }
            let inside = attribute.localizedName[range].dropFirst().dropLast()
            let numbers = inside.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if let top = numbers.max() {
                best = max(best, top)
            }
        }
        return best
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
