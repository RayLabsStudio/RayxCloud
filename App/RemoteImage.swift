// RemoteImage.swift
// Cached image loader. Tries each candidate URL in order, survives task
// cancellation during fast scrolling, and keeps decoded images in memory.
//

import SwiftUI
import UIKit

struct RemoteImage<Placeholder: View>: View {
    let urls: [URL]
    var maxPixelWidth: CGFloat = 600
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var failed = false

    init(urls: [URL?], maxPixelWidth: CGFloat = 600, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.urls = urls.compactMap { $0 }
        self.maxPixelWidth = maxPixelWidth
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
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
        failed = false
        for url in urls {
            if let cached = ImageCache.shared.image(for: url) {
                image = cached
                return
            }
            if let loaded = await ImageCache.shared.fetch(url, maxPixelWidth: maxPixelWidth) {
                image = loaded
                return
            }
            if Task.isCancelled { return }
        }
        failed = true
    }
}

@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 400
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Fetches and decodes once per URL. A view being cancelled mid-scroll does not
    /// cancel the download, so the next appearance gets the finished image.
    func fetch(_ url: URL, maxPixelWidth: CGFloat) async -> UIImage? {
        if let existing = inFlight[url] {
            return await existing.value
        }
        let task = Task<UIImage?, Never>.detached(priority: .utility) {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let decoded = UIImage(data: data) else {
                return nil
            }
            let scale = min(1, maxPixelWidth / max(decoded.size.width, 1))
            let targetSize = CGSize(width: decoded.size.width * scale, height: decoded.size.height * scale)
            return await decoded.byPreparingThumbnail(ofSize: targetSize) ?? decoded
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result {
            cache.setObject(result, forKey: url as NSURL)
        }
        return result
    }
}
