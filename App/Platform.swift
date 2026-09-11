// Platform.swift
// Small helpers that differ between iOS and macOS.
//

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum Platform {
    static func copyToPasteboard(_ text: String) {
#if os(iOS)
        UIPasteboard.general.string = text
#else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#endif
    }

#if os(macOS)
    @MainActor
    static func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }
#endif
}

#if os(macOS)
/// Tracks whether the main window is in full screen so views can keep clear of
/// the traffic lights when it is not. The title bar is hidden, so content runs
/// under them in windowed mode.
@Observable
@MainActor
final class MacWindowState {
    static let shared = MacWindowState()

    private(set) var isFullScreen = false

    /// Horizontal inset that keeps leading controls clear of the traffic lights.
    var leadingInset: CGFloat { isFullScreen ? 0 : 68 }

    private init() {
        isFullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in MacWindowState.shared.isFullScreen = true }
        }
        center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in MacWindowState.shared.isFullScreen = false }
        }
    }
}
#endif
