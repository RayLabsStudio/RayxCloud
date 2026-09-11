// SignInView.swift
// Signed-out landing screen and the Microsoft device-code sign-in flow.
//

import SwiftUI
import StratixCore
import XCloudAPI
#if os(iOS)
import SafariServices
#endif

struct SignInView: View {
    @Environment(SessionController.self) private var sessionController

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.green)

            Text("RayxCloud")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Text("Sign in with the Microsoft account that has Game Pass Ultimate.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if let error = sessionController.lastAuthError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button {
                Task { await sessionController.beginSignIn() }
            } label: {
                Text("Sign in with Microsoft")
                    .font(.headline)
                    .frame(maxWidth: 320)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shows the device code and opens the Microsoft sign-in page. On iOS the page
/// opens inside the app so token polling keeps running in the foreground; on
/// macOS it opens in the default browser while the app keeps polling.
struct DeviceCodeView: View {
    let info: DeviceCodeInfo

    @Environment(\.openURL) private var openURL
    @State private var showBrowser = false
    @State private var didAutoOpen = false

    private var signInURL: URL? {
        URL(string: info.verificationUriComplete ?? info.verificationUri)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Sign in to Xbox")
                .font(.title.weight(.bold))
                .foregroundStyle(.white)

            Text("Enter this code on the Microsoft page if it is not filled in already.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(info.userCode)
                .font(.system(size: 44, weight: .heavy, design: .monospaced))
                .foregroundStyle(.green)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 12) {
                Button {
                    Platform.copyToPasteboard(info.userCode)
                } label: {
                    Label("Copy code", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button {
                    openSignInPage()
                } label: {
                    Label("Open Microsoft sign-in", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(signInURL == nil)
            }

            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("Waiting for you to finish signing in")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#if os(iOS)
        .sheet(isPresented: $showBrowser) {
            if let signInURL {
                SafariView(url: signInURL)
                    .ignoresSafeArea()
            }
        }
#endif
        .onAppear {
            guard !didAutoOpen, signInURL != nil else { return }
            didAutoOpen = true
            openSignInPage()
        }
    }

    private func openSignInPage() {
#if os(iOS)
        showBrowser = true
#else
        if let signInURL {
            openURL(signInURL)
        }
#endif
    }
}

#if os(iOS)
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif
