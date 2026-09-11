// RootView.swift
// Picks the top-level screen from the session's auth state.
//

import SwiftUI
import StratixCore

struct RootView: View {
    @Environment(SessionController.self) private var sessionController

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch sessionController.authState {
            case .unknown:
                ProgressView("Starting")
                    .tint(.white)
                    .foregroundStyle(.white)

            case .unauthenticated:
                SignInView()

            case .authenticating(let info):
                DeviceCodeView(info: info)

            case .authenticated:
                LibraryView()
            }
        }
    }
}
