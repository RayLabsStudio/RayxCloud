# CLAUDE.md

Guidance for AI assistants and new contributors working in this repo.

## What this is

RayxCloud is a native Xbox Cloud Gaming client for iPhone, iPad, and Mac. It is a port of [Stratix](https://github.com/nafields/stratix) (tvOS). The Stratix packages in `Packages/` implement the whole xCloud protocol and are kept as close to upstream as possible. The app shell in `App/` is ours and is shared by both platforms.

License is GPL-3.0. Anything added here must be compatible with that. Do not copy code from repos without a license.

## Layout

```
App/                    SwiftUI shell shared by iOS and macOS
  RayxCloudApp.swift    entry point, builds AppCoordinator from StratixCore
  RootView.swift        auth state switch: sign in / device code / library
  SignInView.swift      Microsoft device-code flow (in-app Safari on iOS, browser on Mac)
  LibraryView.swift     game grid, search field, filter menu, LibraryFilter
  StreamView.swift      full-screen stream, controls, performance overlay toggle
  StreamHUD.swift       performance overlay
  VideoView.swift       AVSampleBufferDisplayLayer renderer (UIView and NSView variants)
  RemoteImage.swift     cached ImageIO-based image loader
  GlassStyle.swift      round glass buttons with pre-26 fallback
  Platform.swift        pasteboard, Mac window state
  DebugLogFile.swift    Debug builds mirror stdout to Documents/rayxcloud.log
  WebRTC/               bridge between StreamingCore and the WebRTC framework (from Stratix)
Packages/               Stratix packages: StratixModels, DiagnosticsKit, InputBridge,
                        XCloudAPI, StreamingCore, VideoRenderingKit, StratixCore
Docs/                   Stratix protocol and architecture docs, still accurate for Packages/
project.yml             XcodeGen spec. Targets: RayxCloud (iOS), RayxCloudMac (macOS)
```

`RayxCloud.xcodeproj` is generated. Edit `project.yml`, then run `xcodegen generate`, and commit both.

## Build

No signing team is committed. Pass it on the command line; never write a team ID into `project.yml` or the pbxproj.

```
xcodegen generate

# iOS device build
xcodebuild -project RayxCloud.xcodeproj -scheme RayxCloud \
  -destination 'generic/platform=iOS' -derivedDataPath DerivedData \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=XXXXXXXXXX build

# iOS Simulator (no signing)
xcodebuild -project RayxCloud.xcodeproj -scheme RayxCloud \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO build

# macOS
xcodebuild -project RayxCloud.xcodeproj -scheme RayxCloudMac \
  -destination 'platform=macOS' -derivedDataPath DerivedData \
  DEVELOPMENT_TEAM=XXXXXXXXXX build
```

Install and launch on a phone without Xcode:

```
xcrun devicectl list devices
xcrun devicectl device install app --device <id> DerivedData/Build/Products/Debug-iphoneos/RayxCloud.app
xcrun devicectl device process launch --device <id> com.raylabsstudio.rayxcloud
```

Pull the Debug log off a phone (no cable needed):

```
xcrun devicectl device copy from --device <id> \
  --domain-type appDataContainer --domain-identifier com.raylabsstudio.rayxcloud \
  --source Documents/rayxcloud.log --destination ./rayxcloud.log
```

On the Mac the same log is at `~/Library/Containers/com.raylabsstudio.rayxcloud/Data/Documents/rayxcloud.log`. The file is reset on every launch.

## Rules

- Swift 6 language mode with strict concurrency on every target. Do not weaken it. Do not add `nonisolated(unsafe)` or `@unchecked Sendable` without a comment explaining why.
- Keep `Packages/` diffable against upstream Stratix. Prefer fixing things in `App/`. When a package change is unavoidable, keep it minimal and platform-guarded so it could be sent upstream.
- All WebRTC-dependent code stays behind `#if WEBRTC_AVAILABLE`, matching Stratix.
- Platform differences go behind `#if os(iOS)` / `#if os(macOS)` in the same file, not in duplicated views.
- iOS deployment target is 17, macOS is 14. Anything from the 26 SDKs (Liquid Glass, new Metal FX APIs) must be behind `#available`.
- Never commit signing teams, device identifiers, log files, or anything under `DerivedData/`.
- Prose in docs and commit messages: plain sentences, no em-dashes.

## Things learned the hard way

- `RTCMTLVideoView` from the stasel/WebRTC build receives frames but draws nothing on iOS 26. Render through `AVSampleBufferDisplayLayer` with `kCMSampleAttachmentKey_DisplayImmediately`. That is what `VideoView.swift` does on both platforms.
- The Mac sandbox needs `com.apple.security.network.server` in addition to `network.client`, or ICE stays in "checking" forever and the stream never connects.
- The stock `VideoRenderingKit` manifest did not declare iOS, and its availability checks named only tvOS and macOS. Both are patched; keep them if you sync from upstream.
- SwiftUI `AsyncImage` gives up permanently when a fast scroll cancels a row of loads. That is why `RemoteImage` exists.
- Audio is receive-only, but WebRTC still opens a play-and-record session, so iOS shows the orange mic dot and both platforms ask for mic permission. Removing that needs a custom output-only `RTCAudioDevice`. Not done yet.
- The device-code poll loop must survive transient `URLError`s or a backgrounded phone loses the sign-in.
- Stream resolution is decided by the server from the spoofed `X-MS-Device-Info` header built in `XCloudAPIClient`. Do not change that header casually; it is what gets 1080p instead of 720p.

## Not built yet

- Touch controls on iPhone and iPad (Microsoft publishes the Touch Adaptation Kit layout schema)
- Keyboard and trackpad as a virtual controller on the Mac, then native mouse and keyboard for titles that support it
- Output-only audio device to drop the microphone session
- Remote Play from a home console (the API code exists in `XCloudAPI`, no UI)
- Controller remapping, DualSense adaptive triggers, gyro
