// GameTile.swift
// Poster tile. On the Mac the name slides in over the art on hover; on iOS it
// sits in a gradient at the bottom so titles never take a second line below.
//

import SwiftUI
import StratixModels

struct GameTile: View {
    let item: CloudLibraryItem
    var width: CGFloat? = nil
    let action: () -> Void

    @State private var isHovering = false

    private var showsName: Bool {
#if os(macOS)
        isHovering
#else
        true
#endif
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(urls: [item.posterImageURL, item.artURL, item.heroImageURL], maxPixelSize: 800) {
                    placeholder
                }

                if showsName {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55), .black.opacity(0.85)],
                        startPoint: .init(x: 0.5, y: 0.45),
                        endPoint: .bottom
                    )
                    Text(item.name)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 9)
                        .transition(.opacity)
                }
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .frame(width: width)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(isHovering ? 0.35 : 0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(isHovering ? 0.5 : 0.25), radius: isHovering ? 14 : 6, y: isHovering ? 8 : 3)
            .scaleEffect(isHovering ? 1.04 : 1)
            .animation(.easeOut(duration: 0.18), value: isHovering)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name)
#if os(macOS)
        .onHover { hovering in
            isHovering = hovering
        }
#endif
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
