// GlassStyle.swift
// Round glass buttons and capsules on iOS 26 / macOS 26, plain translucent
// shapes on older systems.
//

import SwiftUI

extension View {
    /// Round button chrome: Liquid Glass where available, translucent circle otherwise.
    @ViewBuilder
    func roundGlass(fallback: Color = Color.white.opacity(0.12)) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Circle())
        } else {
            self.background(fallback, in: Circle())
        }
    }

    /// Capsule chrome: Liquid Glass where available, translucent capsule otherwise.
    @ViewBuilder
    func capsuleGlass(fallback: Color = Color.white.opacity(0.12), interactive: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: Capsule())
        } else {
            self.background(fallback, in: Capsule())
        }
    }

    /// Makes a Menu render as a plain icon button without the pull-down chevron.
    func iconMenuStyle() -> some View {
        self
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
    }
}

/// A 40 pt round icon used for toolbar and filter buttons.
struct RoundIcon: View {
    let symbol: String
    var tint: Color = .white
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .contentShape(Circle())
            .roundGlass()
    }
}
