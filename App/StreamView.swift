// StreamView.swift
// Full-screen stream surface for one cloud title.
//

import SwiftUI
import StratixCore
import StratixModels
import StreamingCore

struct StreamView: View {
    let item: CloudLibraryItem

    @Environment(StreamController.self) private var streamController
    @Environment(\.dismiss) private var dismiss

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

            if showControls || lifecycle != .connected {
                controls
            }
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleControls()
        }
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
            RemoteImage(urls: [item.heroImageURL, item.artURL, item.posterImageURL], maxPixelWidth: 1600) {
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
            HStack(alignment: .top) {
                Button {
                    exitStream()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(12)
                        .background(.black.opacity(0.6), in: Circle())
                        .foregroundStyle(.white)
                }

                Spacer()

                if lifecycle == .connected {
                    Text(item.name)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule())
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
            print("[StreamView] video track received: \(type(of: track))")
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
        dismiss()
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
