// StreamHUD.swift
// Compact performance overlay: resolution, frame rate, bitrate, latency, loss.
//

import SwiftUI
import StratixModels

struct StreamHUD: View {
    let stats: StreamingStatsSnapshot

    private var latencyLevel: Double {
        // 1.0 at 20 ms or better, 0.0 at 200 ms or worse.
        guard let rtt = stats.roundTripTimeMs else { return 0 }
        return max(0, min(1, 1 - (rtt - 20) / 180))
    }

    private var latencyColor: Color {
        guard let rtt = stats.roundTripTimeMs else { return .secondary }
        if rtt < 60 { return .green }
        if rtt < 120 { return .yellow }
        return .red
    }

    private var bitrateLevel: Double {
        guard let kbps = stats.bitrateKbps else { return 0 }
        return max(0, min(1, Double(kbps) / 20_000))
    }

    private var resolutionText: String? {
        guard let width = stats.negotiatedWidth, let height = stats.negotiatedHeight, height > 0 else { return nil }
        _ = width
        return "\(height)p"
    }

    var body: some View {
        HStack(spacing: 14) {
            if let resolutionText {
                metric(symbol: "rectangle.inset.filled", text: resolutionText)
            }
            if let fps = stats.framesPerSecond {
                metric(symbol: "gauge.with.dots.needle.67percent", text: "\(Int(fps.rounded())) fps")
            }
            if let kbps = stats.bitrateKbps {
                metric(symbol: "cellularbars", variableValue: bitrateLevel, text: String(format: "%.1f Mbps", Double(kbps) / 1000))
            }
            if let rtt = stats.roundTripTimeMs {
                metric(symbol: "wifi", variableValue: latencyLevel, text: "\(Int(rtt.rounded())) ms", color: latencyColor)
            }
            if let lost = stats.packetsLost, lost > 0 {
                metric(symbol: "exclamationmark.triangle.fill", text: "\(lost) lost", color: .orange)
            }
        }
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .capsuleGlass(fallback: .black.opacity(0.6))
        .animation(.easeInOut(duration: 0.3), value: stats.roundTripTimeMs)
    }

    private func metric(symbol: String, variableValue: Double? = nil, text: String, color: Color = .white) -> some View {
        HStack(spacing: 5) {
            if let variableValue {
                Image(systemName: symbol, variableValue: variableValue)
                    .foregroundStyle(color)
            } else {
                Image(systemName: symbol)
                    .foregroundStyle(color)
            }
            Text(text)
        }
    }
}
