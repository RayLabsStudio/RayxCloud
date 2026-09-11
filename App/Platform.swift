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

    @MainActor
    static var isFullScreen: Bool {
        NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false
    }
#endif
}
