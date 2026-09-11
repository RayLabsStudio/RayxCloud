// StreamView.swift
// Full-screen stream surface for one cloud title.
//

import SwiftUI
import StratixCore
import StratixModels
import StreamingCore

struct StreamView: View {
    let item: CloudLibraryItem
    let onClose: () -> Void

    @Environment(StreamController.self) private var streamController
    @AppStorage("hud.enabled") private var hudEnabled = false

    @State private var bridge = WebRTCClientImpl()
    @State private var videoTrack: AnyObject?
    @State private var attachedSessionID: ObjectIdentifier?
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isExiting = false

    private var session: (any StreamingSessionFacade)? {
        streamController.streamingSession
    }

    private var lifecycle: StreamLifecycleState {
        session?.lifecycle ?? .idle
    }

    private var sessionID: ObjectIdentifier? {
        session.map(ObjectIdentifier.init)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if videoTrack != nil {
                VideoView(videoTrack: videoTrack)
                    .ignoresSafeArea()
            } else {
                launchPlaceholder
            }

            if hudEnabled, lifecycle == .connected, let session {
                VStack {
                    Spacer()
                    StreamHUD(stats: session.stats)
                        .padding(.bottom, 14)
                }
                .allowsHitTesting(false)
            }

            if showControls || lifecycle != .connected {
                controls
            }
        }
        .persistentSystemOverlays(.hidden)
#if os(iOS)
        .statusBarHidden(true)
#endif
        .contentShape(Rectangle())
        .onTapGesture {
            toggleControls()
        }
#if os(macOS)
        .onExitCommand {
            revealControls()
        }
        .onHover { hovering in
            if hovering { revealControls() }
        }
#endif
        .task {
            await streamController.startCloudStream(titleId: TitleID(rawValue: item.titleId), bridge: bridge)
        }
        .onChange(of: sessionID, initial: true) { _, _ in
            attachVideoTrackHandler()
        }
        .onChange(of: lifecycle) { _, newValue in
            if newValue == .connected {
                scheduleControlsHide()
            }
        }
        .onDisappear {
            teardown()
        }
    }

    // MARK: - Subviews

    private var launchPlaceholder: some View {
        ZStack {
            RemoteImage(urls: [item.heroImageURL, item.artURL, item.posterImageURL], maxPixelSize: 1920) {
                Color.black
            }
            .overlay(Color.black.opacity(0.55))
            .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView().tint(.white)
                Text(statusText)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    private var controls: some View {
        VStack {
            HStack(alignment: .top, spacing: 10) {
                controlButton(symbol: "xmark", label: "Close stream") {
                    exitStream()
                }

                Spacer()

                if lifecycle == .connected {
                    Text(item.name)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .capsuleGlass(fallback: .black.opacity(0.6))

                    Spacer()

                    controlButton(
                        symbol: hudEnabled ? "gauge.with.dots.needle.67percent" : "gauge.with.dots.needle.0percent",
                        label: hudEnabled ? "Hide performance" : "Show performance",
                        tint: hudEnabled ? .green : .white
                    ) {
                        hudEnabled.toggle()
                        scheduleControlsHide()
                    }
#if os(macOS)
                    controlButton(
                        symbol: Platform.isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                        label: "Toggle full screen"
                    ) {
                        Platform.toggleFullScreen()
                        scheduleControlsHide()
                    }
#endif
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)

            Spacer()

            if case .failed(let error) = lifecycle {
                Text(String(describing: error))
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(.red.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                    .padding(24)
            }
        }
        .transition(.opacity)
    }

    private func controlButton(symbol: String, label: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundIcon(symbol: symbol, tint: tint, size: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var statusText: String {
        switch lifecycle {
        case .idle, .startingSession:
            return "Starting \(item.name)"
        case .provisioning:
            return "Provisioning a cloud console"
        case .waitingForResources(let seconds):
            if let seconds, seconds > 0 {
                return "In queue, about \(seconds / 60) min"
            }
            return "Waiting for a free console"
        case .readyToConnect, .connectingWebRTC:
            return "Connecting"
        case .connected:
            return "Waiting for video"
        case .disconnecting, .disconnected:
            return "Disconnected"
        case .failed(let error):
            return "Stream failed: \(String(describing: error))"
        }
    }

    // MARK: - Behavior

    private func attachVideoTrackHandler() {
        guard sessionID != attachedSessionID else { return }
        attachedSessionID = sessionID
        videoTrack = nil
        guard let session else { return }
        session.setDiagnosticsPollingEnabled(true)
        session.onVideoTrack = { track in
            Task { @MainActor in
                videoTrack = track
            }
        }
    }

    private func toggleControls() {
        guard lifecycle == .connected else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
        if showControls {
            scheduleControlsHide()
        }
    }

    private func revealControls() {
        guard lifecycle == .connected, !showControls else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls = true
        }
        scheduleControlsHide()
    }

    private func scheduleControlsHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls = false
            }
        }
    }

    private func exitStream() {
        guard !isExiting else { return }
        isExiting = true
        Task {
            await streamController.setOverlayVisible(false, trigger: .explicitExit)
            await streamController.stopStreaming()
            await streamController.exitStreamPriorityMode()
        }
        onClose()
    }

    private func teardown() {
        hideControlsTask?.cancel()
        session?.onVideoTrack = nil
        videoTrack = nil
        attachedSessionID = nil
        guard !isExiting else { return }
        Task {
            await streamController.setOverlayVisible(false, trigger: .explicitExit)
            await streamController.stopStreaming()
            await streamController.exitStreamPriorityMode()
        }
    }
}
