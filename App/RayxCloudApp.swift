// RayxCloudApp.swift
// App entry point. Builds the shared controller graph from StratixCore and injects it into SwiftUI.
//

import SwiftUI
import StratixCore

@main
struct RayxCloudApp: App {
    @State private var coordinator = AppCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        DebugLogFile.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(coordinator.sessionController)
                .environment(coordinator.libraryController)
                .environment(coordinator.streamController)
                .environment(coordinator.shellBootstrapController)
                .environment(coordinator.inputController)
                .environment(coordinator.settingsStore)
                .preferredColorScheme(.dark)
                .task {
                    await coordinator.onAppear()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await coordinator.handleAppDidBecomeActive() }
                }
        }
#if os(macOS)
        .defaultSize(width: 1280, height: 800)
#endif
    }
}
