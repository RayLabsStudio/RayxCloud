// RemoteImage.swift
// Cached image loader shared by iOS and macOS. Tries each candidate URL in
// order, survives task cancellation during fast scrolling, decodes with ImageIO
// at a bounded pixel size, and keeps the decoded images in memory.
//

import SwiftUI
import ImageIO

struct RemoteImage<Placeholder: View>: View {
    let urls: [URL]
    var maxPixelSize: CGFloat = 800
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: CGImage?

    init(urls: [URL?], maxPixelSize: CGFloat = 800, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.urls = urls.compactMap { $0 }
        self.maxPixelSize = maxPixelSize
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: urls) {
            await load()
        }
    }

    private func load() async {
        image = nil
        for url in urls {
            if let cached = ImageCache.shared.image(for: url) {
                image = cached
                return
            }
            if let loaded = await ImageCache.shared.fetch(url, maxPixelSize: maxPixelSize) {
                image = loaded
                return
            }
            if Task.isCancelled { return }
        }
    }
}

@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, CGImage>()
    private var inFlight: [URL: Task<CGImage?, Never>] = [:]

    private init() {
        cache.countLimit = 400
    }

    func image(for url: URL) -> CGImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Fetches and decodes once per URL. A view being cancelled mid-scroll does not
    /// cancel the download, so the next appearance gets the finished image.
    func fetch(_ url: URL, maxPixelSize: CGFloat) async -> CGImage? {
        if let existing = inFlight[url] {
            return await existing.value
        }
        let task = Task<CGImage?, Never>.detached(priority: .utility) {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return Self.decode(data, maxPixelSize: maxPixelSize)
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result {
            cache.setObject(result, forKey: url as NSURL)
        }
        return result
    }

    private nonisolated static func decode(_ data: Data, maxPixelSize: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
