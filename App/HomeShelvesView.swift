// HomeShelvesView.swift
// Xbox-style home: horizontal shelves (Jump back in, Recently added, the
// merchandising rows Xbox serves) followed by the full alphabetical grid.
//

import SwiftUI
import StratixCore
import StratixModels

struct GameShelf: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [CloudLibraryItem]
}

struct HomeShelvesView: View {
    let shelves: [GameShelf]
    let allItems: [CloudLibraryItem]
    let tileWidth: CGFloat
    let columns: [GridItem]
    let onSelect: (CloudLibraryItem) -> Void
    let onShowAll: (GameShelf) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 28) {
            ForEach(shelves) { shelf in
                ShelfRow(shelf: shelf, tileWidth: tileWidth, onSelect: onSelect, onShowAll: onShowAll)
            }

            VStack(alignment: .leading, spacing: 12) {
                ShelfHeader(title: "All games", count: allItems.count, showAll: nil)
                    .padding(.horizontal, 16)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(allItems) { item in
                        GameTile(item: item) { onSelect(item) }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 12)
    }
}

private struct ShelfRow: View {
    let shelf: GameShelf
    let tileWidth: CGFloat
    let onSelect: (CloudLibraryItem) -> Void
    let onShowAll: (GameShelf) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShelfHeader(title: shelf.title, count: shelf.items.count) {
                onShowAll(shelf)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(shelf.items) { item in
                        GameTile(item: item, width: tileWidth) { onSelect(item) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .scrollClipDisabled()
        }
    }
}

private struct ShelfHeader: View {
    let title: String
    let count: Int
    let showAll: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let showAll {
                Button("Show all", action: showAll)
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
    }
}
